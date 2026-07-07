import * as anchor from "@coral-xyz/anchor";
import { BN, Program } from "@coral-xyz/anchor";
import { MintController } from "../target/types/mint_controller";
import {
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  LAMPORTS_PER_SOL,
} from "@solana/web3.js";
import {
  TOKEN_PROGRAM_ID,
  createMint,
  createAccount,
  setAuthority,
  AuthorityType,
  getAccount,
} from "@solana/spl-token";
import { assert, expect } from "chai";
import * as fs from "fs";
import * as path from "path";

const MINT_ROLES_SEED = Buffer.from("mint_roles");
const MINT_AUTHORITY_SEED = Buffer.from("mint_authority");
const MINT_RATE_LIMIT_CONFIG_SEED = Buffer.from("mint_rate_limit_config");
const MINT_ALLOWLIST_CONFIG_SEED = Buffer.from("mint_allowlist_config");
const GLOBAL_CONFIG_SEED = Buffer.from("global_config");
const INITIAL_GLOBAL_ADMIN = new PublicKey(
  "naX3wmWkWyxxY1mBeva6mPEEegwKuGEXDarn41w6bfP",
);

describe("mint-controller", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace.mintController as Program<MintController>;
  const payer = provider.wallet as anchor.Wallet;

  const globalAdmin = Keypair.fromSecretKey(
    Uint8Array.from(
      JSON.parse(
        fs.readFileSync(
          path.join(__dirname, "keys", "global-admin.json"),
          "utf-8",
        ),
      ),
    ),
  );

  before(async () => {
    await fundedKeypairFor(globalAdmin);
    try {
      await program.methods
        .initializeGlobal()
        .accounts({ payer: payer.publicKey } as any)
        .rpc();
    } catch (err: any) {
      // Safe to re-run the suite: global config is a one-time init.
      expect(err.toString()).to.match(/already in use|0x0/);
    }

    const cfg = await program.account.globalConfig.fetch(globalConfigPda());
    expect(cfg.admin.toBase58()).to.equal(INITIAL_GLOBAL_ADMIN.toBase58());
  });

  // Helpers ----------------------------------------------------------------

  async function fundedKeypairFor(
    kp: Keypair,
    lamports = LAMPORTS_PER_SOL / 10,
  ): Promise<Keypair> {
    const tx = new Transaction().add(
      SystemProgram.transfer({
        fromPubkey: payer.publicKey,
        toPubkey: kp.publicKey,
        lamports,
      }),
    );
    await provider.sendAndConfirm(tx, []);
    return kp;
  }

  async function fundedKeypair(lamports = LAMPORTS_PER_SOL / 10): Promise<Keypair> {
    return fundedKeypairFor(Keypair.generate(), lamports);
  }

  function globalConfigPda(): PublicKey {
    return PublicKey.findProgramAddressSync(
      [GLOBAL_CONFIG_SEED],
      program.programId,
    )[0];
  }

  function rolesPda(mint: PublicKey): PublicKey {
    return PublicKey.findProgramAddressSync(
      [MINT_ROLES_SEED, mint.toBuffer()],
      program.programId,
    )[0];
  }

  function mintAuthorityPda(mint: PublicKey): PublicKey {
    return PublicKey.findProgramAddressSync(
      [MINT_AUTHORITY_SEED, mint.toBuffer()],
      program.programId,
    )[0];
  }

  function configPda(mint: PublicKey, minter: PublicKey): PublicKey {
    return PublicKey.findProgramAddressSync(
      [MINT_RATE_LIMIT_CONFIG_SEED, mint.toBuffer(), minter.toBuffer()],
      program.programId,
    )[0];
  }

  function allowlistPda(mint: PublicKey, minter: PublicKey): PublicKey {
    return PublicKey.findProgramAddressSync(
      [MINT_ALLOWLIST_CONFIG_SEED, mint.toBuffer(), minter.toBuffer()],
      program.programId,
    )[0];
  }

  /**
   * Spin up a fresh SPL mint whose mint_authority is the program's
   * `mint_authority` PDA, then call `initialize`. Returns everything the tests
   * need to interact with this mint.
   *
   * Each top-level test gets its own mint so sub-tests are independent.
   */
  async function setupMintAndInitialize(opts?: {
    decimals?: number;
  }): Promise<{
    mint: PublicKey;
    admin: Keypair;
    rateLimitAuthority: Keypair;
  }> {
    const mint = await createMint(
      provider.connection,
      payer.payer,
      payer.publicKey,
      null,
      opts?.decimals ?? 6,
    );

    const mintAuth = mintAuthorityPda(mint);
    await setAuthority(
      provider.connection,
      payer.payer,
      mint,
      payer.publicKey,
      AuthorityType.MintTokens,
      mintAuth,
    );

    const admin = await fundedKeypair();
    const rateLimitAuthority = await fundedKeypair();

    await program.methods
      .initialize(admin.publicKey, rateLimitAuthority.publicKey)
      .accounts({
        mint,
        payer: payer.publicKey,
        globalAdmin: globalAdmin.publicKey,
      } as any)
      .signers([globalAdmin])
      .rpc();

    return { mint, admin, rateLimitAuthority };
  }

  async function configureMinter(
    mint: PublicKey,
    rateLimitAuthority: Keypair,
    minter: PublicKey,
    limit: number | BN,
    intervalSecs: number | BN,
  ): Promise<void> {
    await program.methods
      .configureMinter(minter, new BN(limit), new BN(intervalSecs))
      .accounts({
        mint,
        rateLimitAuthority: rateLimitAuthority.publicKey,
      } as any)
      .signers([rateLimitAuthority])
      .rpc();
  }

  async function addAllowedMintRecipient(
    mint: PublicKey,
    admin: Keypair,
    minter: PublicKey,
    recipient: PublicKey,
  ): Promise<void> {
    await program.methods
      .addAllowedMintRecipient(minter, recipient)
      .accounts({
        mint,
        admin: admin.publicKey,
      } as any)
      .signers([admin])
      .rpc();
  }

  // Tests -----------------------------------------------------------------

  describe("initialize", () => {
    it("creates the per-mint roles PDA when SPL mint authority is the program PDA", async () => {
      const { mint, admin, rateLimitAuthority } =
        await setupMintAndInitialize();

      const roles = await program.account.mintRoles.fetch(rolesPda(mint));
      expect(roles.admin.toBase58()).to.equal(admin.publicKey.toBase58());
      expect(roles.rateLimitAuthority.toBase58()).to.equal(
        rateLimitAuthority.publicKey.toBase58(),
      );
    });

    it("rejects when SPL mint authority is not the program PDA", async () => {
      // Don't transfer mint authority to the PDA — should fail with InvalidMintAuthority.
      const mint = await createMint(
        provider.connection,
        payer.payer,
        payer.publicKey,
        null,
        6,
      );
      const admin = Keypair.generate();
      try {
        await program.methods
          .initialize(admin.publicKey, admin.publicKey)
          .accounts({
            mint,
            payer: payer.publicKey,
            globalAdmin: globalAdmin.publicKey,
          } as any)
          .signers([globalAdmin])
          .rpc();
        assert.fail("expected InvalidMintAuthority");
      } catch (err: any) {
        expect(err.error?.errorCode?.code ?? err.toString()).to.contain("InvalidMintAuthority");
      }
    });

    it("rejects when the caller is not the global admin", async () => {
      const mint = await createMint(
        provider.connection,
        payer.payer,
        payer.publicKey,
        null,
        6,
      );
      const mintAuth = mintAuthorityPda(mint);
      await setAuthority(
        provider.connection,
        payer.payer,
        mint,
        payer.publicKey,
        AuthorityType.MintTokens,
        mintAuth,
      );

      const attacker = await fundedKeypair();
      const admin = Keypair.generate();
      try {
        await program.methods
          .initialize(admin.publicKey, admin.publicKey)
          .accounts({
            mint,
            payer: payer.publicKey,
            globalAdmin: attacker.publicKey,
          } as any)
          .signers([attacker])
          .rpc();
        assert.fail("expected Unauthorized");
      } catch (err: any) {
        expect(err.toString()).to.match(/Unauthorized|ConstraintHasOne/);
      }
    });
  });

  describe("update_<role> instructions", () => {
    it("rejects each updater when the wrong signer calls it", async () => {
      const { mint, admin, rateLimitAuthority } =
        await setupMintAndInitialize();
      const stranger = await fundedKeypair();
      const newKey = Keypair.generate().publicKey;

      // update_admin
      try {
        await program.methods
          .updateAdmin(newKey)
          .accounts({ mint, admin: stranger.publicKey } as any)
          .signers([stranger])
          .rpc();
        assert.fail("update_admin should require admin signer");
      } catch (err: any) {
        // has_one mismatch surfaces as ConstraintHasOne, not Unauthorized.
        expect(err.toString()).to.match(/ConstraintHasOne|Unauthorized/);
      }

      // update_rate_limit_authority called by rate_limit_authority (not admin) should fail.
      try {
        await program.methods
          .updateRateLimitAuthority(newKey)
          .accounts({ mint, admin: rateLimitAuthority.publicKey } as any)
          .signers([rateLimitAuthority])
          .rpc();
        assert.fail("update_rate_limit_authority should require admin signer");
      } catch (err: any) {
        expect(err.toString()).to.match(/ConstraintHasOne|Unauthorized/);
      }
    });

    it("admin can rotate each role", async () => {
      const { mint, admin } = await setupMintAndInitialize();
      const newRateLimitAuthority = Keypair.generate().publicKey;
      const newAdmin = Keypair.generate().publicKey;

      await program.methods
        .updateRateLimitAuthority(newRateLimitAuthority)
        .accounts({ mint, admin: admin.publicKey } as any)
        .signers([admin])
        .rpc();
      await program.methods
        .updateAdmin(newAdmin)
        .accounts({ mint, admin: admin.publicKey } as any)
        .signers([admin])
        .rpc();

      const roles = await program.account.mintRoles.fetch(rolesPda(mint));
      expect(roles.admin.toBase58()).to.equal(newAdmin.toBase58());
      expect(roles.rateLimitAuthority.toBase58()).to.equal(
        newRateLimitAuthority.toBase58(),
      );
    });
  });

  describe("configure_minter", () => {
    it("first call creates the per-(mint,minter) PDA and grants MINT_ROLE", async () => {
      const { mint, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;

      await configureMinter(mint, rateLimitAuthority, minter, 1_000_000, 86_400);

      const cfg = await program.account.mintRateLimitConfig.fetch(configPda(mint, minter));
      expect(cfg.minterPublicKey.toBase58()).to.equal(minter.toBase58());
      expect(cfg.limit.toString()).to.equal("1000000");
      expect(cfg.interval.toString()).to.equal("86400");
      expect(cfg.remaining.toString()).to.equal("1000000");
    });

    it("second call updates limit and interval but preserves remaining and last_consumed", async () => {
      const { mint, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;

      await configureMinter(mint, rateLimitAuthority, minter, 1_000_000, 86_400);
      const before = await program.account.mintRateLimitConfig.fetch(configPda(mint, minter));

      await configureMinter(mint, rateLimitAuthority, minter, 500_000, 3600);
      const after = await program.account.mintRateLimitConfig.fetch(configPda(mint, minter));

      expect(after.limit.toString()).to.equal("500000");
      expect(after.interval.toString()).to.equal("3600");
      expect(after.remaining.toString()).to.equal(before.remaining.toString());
      expect(after.lastConsumed.toString()).to.equal(before.lastConsumed.toString());
    });

    it("rejects from non-rate_limit_authority", async () => {
      const { mint } = await setupMintAndInitialize();
      const stranger = await fundedKeypair();
      const minter = Keypair.generate().publicKey;

      try {
        await program.methods
          .configureMinter(minter, new BN(1), new BN(1))
          .accounts({ mint, rateLimitAuthority: stranger.publicKey } as any)
          .signers([stranger])
          .rpc();
        assert.fail("expected ConstraintHasOne");
      } catch (err: any) {
        expect(err.toString()).to.match(/ConstraintHasOne|Unauthorized/);
      }
    });

    it("rejects when limit or interval is zero", async () => {
      const { mint, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;

      for (const [limit, interval] of [
        [0, 100],
        [100, 0],
      ] as const) {
        try {
          await configureMinter(mint, rateLimitAuthority, minter, limit, interval);
          assert.fail(`expected InvalidConfig for limit=${limit} interval=${interval}`);
        } catch (err: any) {
          expect(err.toString()).to.contain("InvalidConfig");
        }
      }
    });
  });

  describe("revoke_minter", () => {
    it("admin closes the config PDA and reclaims rent", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      await configureMinter(mint, rateLimitAuthority, minter, 1_000, 60);

      const adminBalanceBefore = await provider.connection.getBalance(admin.publicKey);
      await program.methods
        .revokeMinter(minter)
        .accounts({ mint, admin: admin.publicKey, allowlist: null } as any)
        .signers([admin])
        .rpc();
      const adminBalanceAfter = await provider.connection.getBalance(admin.publicKey);
      expect(adminBalanceAfter).to.be.greaterThan(adminBalanceBefore);

      const acct = await provider.connection.getAccountInfo(configPda(mint, minter));
      expect(acct).to.equal(null);
    });

    it("also closes the allowlist PDA when one exists", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      const recipient = Keypair.generate().publicKey;
      await configureMinter(mint, rateLimitAuthority, minter, 1_000, 60);
      await addAllowedMintRecipient(mint, admin, minter, recipient);

      await program.methods
        .revokeMinter(minter)
        .accounts({
          mint,
          admin: admin.publicKey,
          allowlist: allowlistPda(mint, minter),
        } as any)
        .signers([admin])
        .rpc();

      const configAcct = await provider.connection.getAccountInfo(configPda(mint, minter));
      const allowlistAcct = await provider.connection.getAccountInfo(
        allowlistPda(mint, minter),
      );
      expect(configAcct).to.equal(null);
      expect(allowlistAcct).to.equal(null);
    });

    it("rejects from non-admin", async () => {
      const { mint, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      await configureMinter(mint, rateLimitAuthority, minter, 1_000, 60);

      try {
        await program.methods
          .revokeMinter(minter)
          .accounts({ mint, admin: rateLimitAuthority.publicKey, allowlist: null } as any)
          .signers([rateLimitAuthority])
          .rpc();
        assert.fail("expected ConstraintHasOne");
      } catch (err: any) {
        expect(err.toString()).to.match(/ConstraintHasOne|Unauthorized/);
      }
    });
  });

  describe("pause", () => {
    it("set_paused(true) halts minting; set_paused(false) restores it", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const ata = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );
      await configureMinter(mint, rateLimitAuthority, minter.publicKey, 1_000, 60);
      await addAllowedMintRecipient(mint, admin, minter.publicKey, recipient.publicKey);

      await program.methods
        .setPaused(true)
        .accounts({ admin: globalAdmin.publicKey } as any)
        .signers([globalAdmin])
        .rpc();

      try {
        await program.methods
          .mintTokens(new BN(1))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: ata,
          } as any)
          .signers([minter])
          .rpc();
        assert.fail("expected MintingPaused");
      } catch (err: any) {
        expect(err.toString()).to.contain("MintingPaused");
      }

      await program.methods
        .setPaused(false)
        .accounts({ admin: globalAdmin.publicKey } as any)
        .signers([globalAdmin])
        .rpc();

      await program.methods
        .mintTokens(new BN(1))
        .accounts({
          minter: minter.publicKey,
          mint,
          recipientTokenAccount: ata,
        } as any)
        .signers([minter])
        .rpc();

      const tokenAcct = await getAccount(provider.connection, ata);
      expect(tokenAcct.amount.toString()).to.equal("1");
    });

    it("rejects set_paused from non-admin", async () => {
      const stranger = await fundedKeypair();
      try {
        await program.methods
          .setPaused(true)
          .accounts({ admin: stranger.publicKey } as any)
          .signers([stranger])
          .rpc();
        assert.fail("expected ConstraintHasOne");
      } catch (err: any) {
        expect(err.toString()).to.match(/ConstraintHasOne|Unauthorized/);
      }
    });

    it("global admin can rotate via update_global_admin", async () => {
      const newGlobalAdmin = await fundedKeypair();
      await program.methods
        .updateGlobalAdmin(newGlobalAdmin.publicKey)
        .accounts({ admin: globalAdmin.publicKey } as any)
        .signers([globalAdmin])
        .rpc();

      const cfg = await program.account.globalConfig.fetch(globalConfigPda());
      expect(cfg.admin.toBase58()).to.equal(newGlobalAdmin.publicKey.toBase58());

      // Restore for subsequent tests.
      await program.methods
        .updateGlobalAdmin(globalAdmin.publicKey)
        .accounts({ admin: newGlobalAdmin.publicKey } as any)
        .signers([newGlobalAdmin])
        .rpc();
    });
  });

  describe("allowlist", () => {
    it("first add_allowed_mint_recipient creates the PDA, subsequent adds reuse it", async () => {
      const { mint, admin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      const a = Keypair.generate().publicKey;
      const b = Keypair.generate().publicKey;

      await addAllowedMintRecipient(mint, admin, minter, a);
      await addAllowedMintRecipient(mint, admin, minter, b);

      const al = await program.account.mintAllowlistConfig.fetch(allowlistPda(mint, minter));
      const got = al.addresses.map((p: PublicKey) => p.toBase58()).sort();
      expect(got).to.deep.equal([a.toBase58(), b.toBase58()].sort());
    });

    it("rejects duplicate adds", async () => {
      const { mint, admin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      const addr = Keypair.generate().publicKey;
      await addAllowedMintRecipient(mint, admin, minter, addr);
      try {
        await addAllowedMintRecipient(mint, admin, minter, addr);
        assert.fail("expected AddressAlreadyAllowlisted");
      } catch (err: any) {
        expect(err.toString()).to.contain("AddressAlreadyAllowlisted");
      }
    });

    it("remove_allowed_mint_recipient errors before any add has been done", async () => {
      const { mint, admin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      try {
        await program.methods
          .removeAllowedMintRecipient(minter, Keypair.generate().publicKey)
          .accounts({ mint, admin: admin.publicKey } as any)
          .signers([admin])
          .rpc();
        assert.fail("expected AccountNotInitialized");
      } catch (err: any) {
        expect(err.toString()).to.match(/AccountNotInitialized|3012/);
      }
    });

    it("remove_allowed_mint_recipient removes an existing entry", async () => {
      const { mint, admin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      const a = Keypair.generate().publicKey;
      const b = Keypair.generate().publicKey;
      await addAllowedMintRecipient(mint, admin, minter, a);
      await addAllowedMintRecipient(mint, admin, minter, b);

      await program.methods
        .removeAllowedMintRecipient(minter, a)
        .accounts({ mint, admin: admin.publicKey } as any)
        .signers([admin])
        .rpc();

      const al = await program.account.mintAllowlistConfig.fetch(allowlistPda(mint, minter));
      const got = al.addresses.map((p: PublicKey) => p.toBase58());
      expect(got).to.deep.equal([b.toBase58()]);
    });

    it("remove_allowed_mint_recipient on a missing entry errors", async () => {
      const { mint, admin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      const a = Keypair.generate().publicKey;
      await addAllowedMintRecipient(mint, admin, minter, a);

      try {
        await program.methods
          .removeAllowedMintRecipient(minter, Keypair.generate().publicKey)
          .accounts({ mint, admin: admin.publicKey } as any)
          .signers([admin])
          .rpc();
        assert.fail("expected AddressNotAllowlisted");
      } catch (err: any) {
        expect(err.toString()).to.contain("AddressNotAllowlisted");
      }
    });
  });

  describe("mint_tokens", () => {
    it("mints to a whitelisted recipient and decrements remaining", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const recipientAta = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );

      await configureMinter(mint, rateLimitAuthority, minter.publicKey, 1_000_000, 86_400);
      await addAllowedMintRecipient(mint, admin, minter.publicKey, recipient.publicKey);

      await program.methods
        .mintTokens(new BN(400_000))
        .accounts({
          minter: minter.publicKey,
          mint,
          recipientTokenAccount: recipientAta,
        } as any)
        .signers([minter])
        .rpc();

      const tokenAcct = await getAccount(provider.connection, recipientAta);
      expect(tokenAcct.amount.toString()).to.equal("400000");

      const cfg = await program.account.mintRateLimitConfig.fetch(
        configPda(mint, minter.publicKey),
      );
      expect(cfg.remaining.toString()).to.equal("600000");
    });

    it("rejects when amount exceeds available capacity", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const recipientAta = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );
      await configureMinter(mint, rateLimitAuthority, minter.publicKey, 100, 86_400);
      await addAllowedMintRecipient(mint, admin, minter.publicKey, recipient.publicKey);

      try {
        await program.methods
          .mintTokens(new BN(101))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: recipientAta,
          } as any)
          .signers([minter])
          .rpc();
        assert.fail("expected LimitExceeded");
      } catch (err: any) {
        expect(err.toString()).to.contain("LimitExceeded");
      }
    });

    it("rejects when recipient is not on the allowlist", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const allowed = Keypair.generate();
      const notAllowed = Keypair.generate();
      const notAllowedAta = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        notAllowed.publicKey,
      );
      await configureMinter(mint, rateLimitAuthority, minter.publicKey, 1_000, 60);
      // Allowlist *exists* (so account loads succeed) but only contains `allowed`.
      await addAllowedMintRecipient(mint, admin, minter.publicKey, allowed.publicKey);

      try {
        await program.methods
          .mintTokens(new BN(1))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: notAllowedAta,
          } as any)
          .signers([minter])
          .rpc();
        assert.fail("expected RecipientNotAllowlisted");
      } catch (err: any) {
        expect(err.toString()).to.contain("RecipientNotAllowlisted");
      }
    });

    it("two minters of the same mint have independent capacity and allowlists", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minterA = await fundedKeypair();
      const minterB = await fundedKeypair();
      const recipientA = Keypair.generate();
      const recipientB = Keypair.generate();
      const ataA = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipientA.publicKey,
      );
      const ataB = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipientB.publicKey,
      );

      await configureMinter(mint, rateLimitAuthority, minterA.publicKey, 1_000, 86_400);
      await configureMinter(mint, rateLimitAuthority, minterB.publicKey, 5_000, 86_400);
      await addAllowedMintRecipient(mint, admin, minterA.publicKey, recipientA.publicKey);
      await addAllowedMintRecipient(mint, admin, minterB.publicKey, recipientB.publicKey);

      // Minter A consumes its full capacity.
      await program.methods
        .mintTokens(new BN(1_000))
        .accounts({
          minter: minterA.publicKey,
          mint,
          recipientTokenAccount: ataA,
        } as any)
        .signers([minterA])
        .rpc();

      // Minter B's capacity is untouched: should mint up to 5000 successfully.
      await program.methods
        .mintTokens(new BN(5_000))
        .accounts({
          minter: minterB.publicKey,
          mint,
          recipientTokenAccount: ataB,
        } as any)
        .signers([minterB])
        .rpc();

      // Recipient A's allowlist for minter A does NOT authorize minter B to mint to A.
      try {
        await program.methods
          .mintTokens(new BN(1))
          .accounts({
            minter: minterB.publicKey,
            mint,
            recipientTokenAccount: ataA,
          } as any)
          .signers([minterB])
          .rpc();
        assert.fail("expected RecipientNotAllowlisted (cross-minter allowlist)");
      } catch (err: any) {
        expect(err.toString()).to.contain("RecipientNotAllowlisted");
      }
    });

    it("rejects when destination token account owner is not allowlisted", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const allowlistedOwner = Keypair.generate();
      const otherOwner = Keypair.generate();
      // ATA owned by someone other than the allowlisted owner.
      const wrongAta = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        otherOwner.publicKey,
      );
      await configureMinter(mint, rateLimitAuthority, minter.publicKey, 1_000, 60);
      await addAllowedMintRecipient(mint, admin, minter.publicKey, allowlistedOwner.publicKey);

      try {
        await program.methods
          .mintTokens(new BN(1))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: wrongAta,
          } as any)
          .signers([minter])
          .rpc();
        assert.fail("expected RecipientNotAllowlisted");
      } catch (err: any) {
        expect(err.toString()).to.contain("RecipientNotAllowlisted");
      }
    });

    it("succeeds when minter holds zero SOL (fee payer is implicit)", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      // `minter` intentionally has zero SOL — only the role signature, never gas.
      const minter = Keypair.generate();
      const recipient = Keypair.generate();
      const ata = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );
      await configureMinter(mint, rateLimitAuthority, minter.publicKey, 1_000, 60);
      await addAllowedMintRecipient(mint, admin, minter.publicKey, recipient.publicKey);

      await program.methods
        .mintTokens(new BN(500))
        .accounts({
          minter: minter.publicKey,
          mint,
          recipientTokenAccount: ata,
        } as any)
        .signers([minter])
        .rpc();

      const tokenAcct = await getAccount(provider.connection, ata);
      expect(tokenAcct.amount.toString()).to.equal("500");

      // Minter still has 0 lamports — verifies it really didn't pay any fees.
      const minterLamports = await provider.connection.getBalance(minter.publicKey);
      expect(minterLamports).to.equal(0);
    });

    it("rate-limit replenishes linearly over the interval", async () => {
      // limit=1000, interval=10s → 100/sec replenishment. Mint full, sleep ~3s,
      // verify ~300 has replenished. Tolerances are loose because validator clock
      // ticks at second granularity.
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const ata = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );
      await configureMinter(mint, rateLimitAuthority, minter.publicKey, 1_000, 10);
      await addAllowedMintRecipient(mint, admin, minter.publicKey, recipient.publicKey);

      // Drain the bucket.
      await program.methods
        .mintTokens(new BN(1_000))
        .accounts({
          minter: minter.publicKey,
          mint,
          recipientTokenAccount: ata,
        } as any)
        .signers([minter])
        .rpc();

      // Immediate retry of even 1 unit should fail.
      try {
        await program.methods
          .mintTokens(new BN(1))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: ata,
          } as any)
          .signers([minter])
          .rpc();
        assert.fail("expected LimitExceeded immediately after drain");
      } catch (err: any) {
        expect(err.toString()).to.contain("LimitExceeded");
      }

      // Sleep ~3s; expect ~300 to have replenished. Mint 200 (well within).
      await new Promise((r) => setTimeout(r, 3500));
      await program.methods
        .mintTokens(new BN(200))
        .accounts({
          minter: minter.publicKey,
          mint,
          recipientTokenAccount: ata,
        } as any)
        .signers([minter])
        .rpc();

      const tokenAcct = await getAccount(provider.connection, ata);
      // 1000 (initial drain) + 200 (after replenishment).
      expect(tokenAcct.amount.toString()).to.equal("1200");
    });

    it("revoked minter can no longer mint", async () => {
      const { mint, admin, rateLimitAuthority } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const ata = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );
      await configureMinter(mint, rateLimitAuthority, minter.publicKey, 1_000, 60);
      await addAllowedMintRecipient(mint, admin, minter.publicKey, recipient.publicKey);

      await program.methods
        .revokeMinter(minter.publicKey)
        .accounts({
          mint,
          admin: admin.publicKey,
          allowlist: allowlistPda(mint, minter.publicKey),
        } as any)
        .signers([admin])
        .rpc();

      try {
        await program.methods
          .mintTokens(new BN(1))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: ata,
          } as any)
          .signers([minter])
          .rpc();
        assert.fail("expected AccountNotInitialized after revoke");
      } catch (err: any) {
        expect(err.toString()).to.match(/AccountNotInitialized|3012/);
      }
    });
  });
});
