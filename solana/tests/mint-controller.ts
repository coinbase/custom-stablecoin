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

const MINT_ROLES_SEED = Buffer.from("mint_roles");
const MINT_AUTHORITY_SEED = Buffer.from("mint_authority");
const MINT_RATE_LIMIT_CONFIG_SEED = Buffer.from("mint_rate_limit_config");
const MINT_ALLOWLIST_CONFIG_SEED = Buffer.from("mint_allowlist_config");

describe("mint-controller", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace.mintController as Program<MintController>;
  const payer = provider.wallet as anchor.Wallet;

  // Helpers ----------------------------------------------------------------

  // Fund a fresh keypair from the provider wallet via SystemProgram.transfer
  // rather than `requestAirdrop`, because the local test-validator's airdrop
  // RPC is rate-limited / unreliable under the parallel load anchor-test creates.
  async function fundedKeypair(lamports = LAMPORTS_PER_SOL / 10): Promise<Keypair> {
    const kp = Keypair.generate();
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
    rateLimitAdmin: Keypair;
    allowlistAdmin: Keypair;
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
    const rateLimitAdmin = await fundedKeypair();
    const allowlistAdmin = await fundedKeypair();

    await program.methods
      .initialize(admin.publicKey, rateLimitAdmin.publicKey, allowlistAdmin.publicKey)
      .accounts({
        mint,
        payer: payer.publicKey,
      } as any)
      .rpc();

    return { mint, admin, rateLimitAdmin, allowlistAdmin };
  }

  async function configureMinter(
    mint: PublicKey,
    rateLimitAdmin: Keypair,
    minter: PublicKey,
    limit: number | BN,
    intervalSecs: number | BN,
  ): Promise<void> {
    await program.methods
      .configureMinter(minter, new BN(limit), new BN(intervalSecs))
      .accounts({
        mint,
        rateLimitAdmin: rateLimitAdmin.publicKey,
      } as any)
      .signers([rateLimitAdmin])
      .rpc();
  }

  async function addToAllowlist(
    mint: PublicKey,
    allowlistAdmin: Keypair,
    minter: PublicKey,
    address: PublicKey,
  ): Promise<void> {
    await program.methods
      .addToAllowlist(minter, address)
      .accounts({
        mint,
        allowlistAdmin: allowlistAdmin.publicKey,
      } as any)
      .signers([allowlistAdmin])
      .rpc();
  }

  // Tests -----------------------------------------------------------------

  describe("initialize", () => {
    it("creates the per-mint roles PDA when SPL mint authority is the program PDA", async () => {
      const { mint, admin, rateLimitAdmin, allowlistAdmin } =
        await setupMintAndInitialize();

      const roles = await program.account.mintRoles.fetch(rolesPda(mint));
      expect(roles.admin.toBase58()).to.equal(admin.publicKey.toBase58());
      expect(roles.rateLimitAdmin.toBase58()).to.equal(rateLimitAdmin.publicKey.toBase58());
      expect(roles.allowlistAdmin.toBase58()).to.equal(allowlistAdmin.publicKey.toBase58());
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
          .initialize(admin.publicKey, admin.publicKey, admin.publicKey)
          .accounts({ mint, payer: payer.publicKey } as any)
          .rpc();
        assert.fail("expected InvalidMintAuthority");
      } catch (err: any) {
        expect(err.error?.errorCode?.code ?? err.toString()).to.contain("InvalidMintAuthority");
      }
    });
  });

  describe("update_<role> instructions", () => {
    it("rejects each updater when the wrong signer calls it", async () => {
      const { mint, admin, rateLimitAdmin, allowlistAdmin } =
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

      // update_rate_limit_admin called by rate_limit_admin (not admin) should fail.
      try {
        await program.methods
          .updateRateLimitAdmin(newKey)
          .accounts({ mint, admin: rateLimitAdmin.publicKey } as any)
          .signers([rateLimitAdmin])
          .rpc();
        assert.fail("update_rate_limit_admin should require admin signer");
      } catch (err: any) {
        expect(err.toString()).to.match(/ConstraintHasOne|Unauthorized/);
      }

      // update_allowlist_admin called by allowlist_admin (not admin) should fail.
      try {
        await program.methods
          .updateAllowlistAdmin(newKey)
          .accounts({ mint, admin: allowlistAdmin.publicKey } as any)
          .signers([allowlistAdmin])
          .rpc();
        assert.fail("update_allowlist_admin should require admin signer");
      } catch (err: any) {
        expect(err.toString()).to.match(/ConstraintHasOne|Unauthorized/);
      }
    });

    it("admin can rotate each role", async () => {
      const { mint, admin } = await setupMintAndInitialize();
      const newRateLimitAdmin = Keypair.generate().publicKey;
      const newAllowlistAdmin = Keypair.generate().publicKey;
      const newAdmin = Keypair.generate().publicKey;

      await program.methods
        .updateRateLimitAdmin(newRateLimitAdmin)
        .accounts({ mint, admin: admin.publicKey } as any)
        .signers([admin])
        .rpc();
      await program.methods
        .updateAllowlistAdmin(newAllowlistAdmin)
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
      expect(roles.rateLimitAdmin.toBase58()).to.equal(newRateLimitAdmin.toBase58());
      expect(roles.allowlistAdmin.toBase58()).to.equal(newAllowlistAdmin.toBase58());
    });
  });

  describe("configure_minter", () => {
    it("first call creates the per-(mint,minter) PDA and grants MINT_ROLE", async () => {
      const { mint, rateLimitAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;

      await configureMinter(mint, rateLimitAdmin, minter, 1_000_000, 86_400);

      const cfg = await program.account.mintRateLimitConfig.fetch(configPda(mint, minter));
      expect(cfg.minterPublicKey.toBase58()).to.equal(minter.toBase58());
      expect(cfg.limit.toString()).to.equal("1000000");
      expect(cfg.interval.toString()).to.equal("86400");
      expect(cfg.remaining.toString()).to.equal("1000000");
    });

    it("second call updates limit and interval but preserves remaining and last_consumed", async () => {
      const { mint, rateLimitAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;

      await configureMinter(mint, rateLimitAdmin, minter, 1_000_000, 86_400);
      const before = await program.account.mintRateLimitConfig.fetch(configPda(mint, minter));

      await configureMinter(mint, rateLimitAdmin, minter, 500_000, 3600);
      const after = await program.account.mintRateLimitConfig.fetch(configPda(mint, minter));

      expect(after.limit.toString()).to.equal("500000");
      expect(after.interval.toString()).to.equal("3600");
      expect(after.remaining.toString()).to.equal(before.remaining.toString());
      expect(after.lastConsumed.toString()).to.equal(before.lastConsumed.toString());
    });

    it("rejects from non-rate_limit_admin", async () => {
      const { mint } = await setupMintAndInitialize();
      const stranger = await fundedKeypair();
      const minter = Keypair.generate().publicKey;

      try {
        await program.methods
          .configureMinter(minter, new BN(1), new BN(1))
          .accounts({ mint, rateLimitAdmin: stranger.publicKey } as any)
          .signers([stranger])
          .rpc();
        assert.fail("expected ConstraintHasOne");
      } catch (err: any) {
        expect(err.toString()).to.match(/ConstraintHasOne|Unauthorized/);
      }
    });

    it("rejects when limit or interval is zero", async () => {
      const { mint, rateLimitAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;

      for (const [limit, interval] of [
        [0, 100],
        [100, 0],
      ] as const) {
        try {
          await configureMinter(mint, rateLimitAdmin, minter, limit, interval);
          assert.fail(`expected InvalidConfig for limit=${limit} interval=${interval}`);
        } catch (err: any) {
          expect(err.toString()).to.contain("InvalidConfig");
        }
      }
    });
  });

  describe("revoke_minter", () => {
    it("admin closes the config PDA and reclaims rent", async () => {
      const { mint, admin, rateLimitAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      await configureMinter(mint, rateLimitAdmin, minter, 1_000, 60);

      const adminBalanceBefore = await provider.connection.getBalance(admin.publicKey);
      await program.methods
        .revokeMinter(minter)
        .accounts({ mint, admin: admin.publicKey } as any)
        .signers([admin])
        .rpc();
      const adminBalanceAfter = await provider.connection.getBalance(admin.publicKey);
      expect(adminBalanceAfter).to.be.greaterThan(adminBalanceBefore);

      const acct = await provider.connection.getAccountInfo(configPda(mint, minter));
      expect(acct).to.equal(null);
    });

    it("rejects from non-admin", async () => {
      const { mint, rateLimitAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      await configureMinter(mint, rateLimitAdmin, minter, 1_000, 60);

      try {
        await program.methods
          .revokeMinter(minter)
          .accounts({ mint, admin: rateLimitAdmin.publicKey } as any)
          .signers([rateLimitAdmin])
          .rpc();
        assert.fail("expected ConstraintHasOne");
      } catch (err: any) {
        expect(err.toString()).to.match(/ConstraintHasOne|Unauthorized/);
      }
    });
  });

  describe("allowlist", () => {
    it("first add_to_allowlist creates the PDA, subsequent adds reuse it", async () => {
      const { mint, allowlistAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      const a = Keypair.generate().publicKey;
      const b = Keypair.generate().publicKey;

      await addToAllowlist(mint, allowlistAdmin, minter, a);
      await addToAllowlist(mint, allowlistAdmin, minter, b);

      const al = await program.account.mintAllowlistConfig.fetch(allowlistPda(mint, minter));
      const got = al.addresses.map((p: PublicKey) => p.toBase58()).sort();
      expect(got).to.deep.equal([a.toBase58(), b.toBase58()].sort());
    });

    it("rejects duplicate adds", async () => {
      const { mint, allowlistAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      const addr = Keypair.generate().publicKey;
      await addToAllowlist(mint, allowlistAdmin, minter, addr);
      try {
        await addToAllowlist(mint, allowlistAdmin, minter, addr);
        assert.fail("expected AddressAlreadyAllowlisted");
      } catch (err: any) {
        expect(err.toString()).to.contain("AddressAlreadyAllowlisted");
      }
    });

    it("remove_from_allowlist errors before any add has been done", async () => {
      const { mint, allowlistAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      try {
        await program.methods
          .removeFromAllowlist(minter, Keypair.generate().publicKey)
          .accounts({ mint, allowlistAdmin: allowlistAdmin.publicKey } as any)
          .signers([allowlistAdmin])
          .rpc();
        assert.fail("expected AccountNotInitialized");
      } catch (err: any) {
        expect(err.toString()).to.match(/AccountNotInitialized|3012/);
      }
    });

    it("remove_from_allowlist removes an existing entry", async () => {
      const { mint, allowlistAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      const a = Keypair.generate().publicKey;
      const b = Keypair.generate().publicKey;
      await addToAllowlist(mint, allowlistAdmin, minter, a);
      await addToAllowlist(mint, allowlistAdmin, minter, b);

      await program.methods
        .removeFromAllowlist(minter, a)
        .accounts({ mint, allowlistAdmin: allowlistAdmin.publicKey } as any)
        .signers([allowlistAdmin])
        .rpc();

      const al = await program.account.mintAllowlistConfig.fetch(allowlistPda(mint, minter));
      const got = al.addresses.map((p: PublicKey) => p.toBase58());
      expect(got).to.deep.equal([b.toBase58()]);
    });

    it("remove_from_allowlist on a missing entry errors", async () => {
      const { mint, allowlistAdmin } = await setupMintAndInitialize();
      const minter = Keypair.generate().publicKey;
      const a = Keypair.generate().publicKey;
      await addToAllowlist(mint, allowlistAdmin, minter, a);

      try {
        await program.methods
          .removeFromAllowlist(minter, Keypair.generate().publicKey)
          .accounts({ mint, allowlistAdmin: allowlistAdmin.publicKey } as any)
          .signers([allowlistAdmin])
          .rpc();
        assert.fail("expected AddressNotAllowlisted");
      } catch (err: any) {
        expect(err.toString()).to.contain("AddressNotAllowlisted");
      }
    });
  });

  describe("mint_tokens", () => {
    it("mints to a whitelisted recipient and decrements remaining", async () => {
      const { mint, rateLimitAdmin, allowlistAdmin } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const recipientAta = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );

      await configureMinter(mint, rateLimitAdmin, minter.publicKey, 1_000_000, 86_400);
      await addToAllowlist(mint, allowlistAdmin, minter.publicKey, recipient.publicKey);

      await program.methods
        .mintTokens(new BN(400_000))
        .accounts({
          minter: minter.publicKey,
          mint,
          recipientTokenAccount: recipientAta,
          recipient: recipient.publicKey,
          payer: payer.publicKey,
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
      const { mint, rateLimitAdmin, allowlistAdmin } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const recipientAta = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );
      await configureMinter(mint, rateLimitAdmin, minter.publicKey, 100, 86_400);
      await addToAllowlist(mint, allowlistAdmin, minter.publicKey, recipient.publicKey);

      try {
        await program.methods
          .mintTokens(new BN(101))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: recipientAta,
            recipient: recipient.publicKey,
            payer: payer.publicKey,
          } as any)
          .signers([minter])
          .rpc();
        assert.fail("expected LimitExceeded");
      } catch (err: any) {
        expect(err.toString()).to.contain("LimitExceeded");
      }
    });

    it("rejects when recipient is not on the allowlist", async () => {
      const { mint, rateLimitAdmin, allowlistAdmin } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const allowed = Keypair.generate();
      const notAllowed = Keypair.generate();
      const notAllowedAta = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        notAllowed.publicKey,
      );
      await configureMinter(mint, rateLimitAdmin, minter.publicKey, 1_000, 60);
      // Allowlist *exists* (so account loads succeed) but only contains `allowed`.
      await addToAllowlist(mint, allowlistAdmin, minter.publicKey, allowed.publicKey);

      try {
        await program.methods
          .mintTokens(new BN(1))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: notAllowedAta,
            recipient: notAllowed.publicKey,
            payer: payer.publicKey,
          } as any)
          .signers([minter])
          .rpc();
        assert.fail("expected RecipientNotAllowlisted");
      } catch (err: any) {
        expect(err.toString()).to.contain("RecipientNotAllowlisted");
      }
    });

    it("two minters of the same mint have independent capacity and allowlists", async () => {
      const { mint, rateLimitAdmin, allowlistAdmin } = await setupMintAndInitialize();
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

      await configureMinter(mint, rateLimitAdmin, minterA.publicKey, 1_000, 86_400);
      await configureMinter(mint, rateLimitAdmin, minterB.publicKey, 5_000, 86_400);
      await addToAllowlist(mint, allowlistAdmin, minterA.publicKey, recipientA.publicKey);
      await addToAllowlist(mint, allowlistAdmin, minterB.publicKey, recipientB.publicKey);

      // Minter A consumes its full capacity.
      await program.methods
        .mintTokens(new BN(1_000))
        .accounts({
          minter: minterA.publicKey,
          mint,
          recipientTokenAccount: ataA,
          recipient: recipientA.publicKey,
          payer: payer.publicKey,
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
          recipient: recipientB.publicKey,
          payer: payer.publicKey,
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
            recipient: recipientA.publicKey,
            payer: payer.publicKey,
          } as any)
          .signers([minterB])
          .rpc();
        assert.fail("expected RecipientNotAllowlisted (cross-minter allowlist)");
      } catch (err: any) {
        expect(err.toString()).to.contain("RecipientNotAllowlisted");
      }
    });

    it("rejects when recipient_token_account.authority != recipient", async () => {
      const { mint, rateLimitAdmin, allowlistAdmin } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const otherOwner = Keypair.generate();
      // ATA owned by someone other than `recipient`.
      const wrongAta = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        otherOwner.publicKey,
      );
      await configureMinter(mint, rateLimitAdmin, minter.publicKey, 1_000, 60);
      await addToAllowlist(mint, allowlistAdmin, minter.publicKey, recipient.publicKey);

      try {
        await program.methods
          .mintTokens(new BN(1))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: wrongAta,
            recipient: recipient.publicKey,
            payer: payer.publicKey,
          } as any)
          .signers([minter])
          .rpc();
        assert.fail("expected ConstraintTokenOwner");
      } catch (err: any) {
        expect(err.toString()).to.match(/ConstraintTokenOwner|TokenOwnerMismatch/);
      }
    });

    it("succeeds when payer != minter (role / fee-payer split)", async () => {
      const { mint, rateLimitAdmin, allowlistAdmin } = await setupMintAndInitialize();
      // `minter` intentionally has zero SOL — only the role signature, never gas.
      const minter = Keypair.generate();
      const recipient = Keypair.generate();
      const ata = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );
      await configureMinter(mint, rateLimitAdmin, minter.publicKey, 1_000, 60);
      await addToAllowlist(mint, allowlistAdmin, minter.publicKey, recipient.publicKey);

      await program.methods
        .mintTokens(new BN(500))
        .accounts({
          minter: minter.publicKey,
          mint,
          recipientTokenAccount: ata,
          recipient: recipient.publicKey,
          payer: payer.publicKey,
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
      const { mint, rateLimitAdmin, allowlistAdmin } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const ata = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );
      await configureMinter(mint, rateLimitAdmin, minter.publicKey, 1_000, 10);
      await addToAllowlist(mint, allowlistAdmin, minter.publicKey, recipient.publicKey);

      // Drain the bucket.
      await program.methods
        .mintTokens(new BN(1_000))
        .accounts({
          minter: minter.publicKey,
          mint,
          recipientTokenAccount: ata,
          recipient: recipient.publicKey,
          payer: payer.publicKey,
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
            recipient: recipient.publicKey,
            payer: payer.publicKey,
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
          recipient: recipient.publicKey,
          payer: payer.publicKey,
        } as any)
        .signers([minter])
        .rpc();

      const tokenAcct = await getAccount(provider.connection, ata);
      // 1000 (initial drain) + 200 (after replenishment).
      expect(tokenAcct.amount.toString()).to.equal("1200");
    });

    it("revoked minter can no longer mint", async () => {
      const { mint, admin, rateLimitAdmin, allowlistAdmin } = await setupMintAndInitialize();
      const minter = await fundedKeypair();
      const recipient = Keypair.generate();
      const ata = await createAccount(
        provider.connection,
        payer.payer,
        mint,
        recipient.publicKey,
      );
      await configureMinter(mint, rateLimitAdmin, minter.publicKey, 1_000, 60);
      await addToAllowlist(mint, allowlistAdmin, minter.publicKey, recipient.publicKey);

      await program.methods
        .revokeMinter(minter.publicKey)
        .accounts({ mint, admin: admin.publicKey } as any)
        .signers([admin])
        .rpc();

      try {
        await program.methods
          .mintTokens(new BN(1))
          .accounts({
            minter: minter.publicKey,
            mint,
            recipientTokenAccount: ata,
            recipient: recipient.publicKey,
            payer: payer.publicKey,
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
