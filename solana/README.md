# Solana mint controller

On-chain mint rate limiting and recipient allowlisting for Solana SPL stablecoins. Mirrors the
EVM rate-limit semantics from [`evm/src/lib/RateLimit.sol`](../evm/src/lib/RateLimit.sol)
and the per-stablecoin role model in [`evm/src/Stablecoin.sol`](../evm/src/Stablecoin.sol).

## Why

A custom stablecoin's SPL mint authority is a single private key; if it leaks, an attacker can mint
unbounded supply. This program lets the mint authority be a program-derived address (PDA) instead,
and gates `mint_to` calls behind:

1. **Per-(mint, minter) rate limiting** — each minter accumulates capacity at `limit / interval`
   tokens per second, capped at `limit`. Matches the EVM `RateLimit` `mulDiv` formula exactly.
2. **Per-(mint, minter) recipient allowlist** — only addresses on the minter's allowlist can
   receive minted tokens. The allowlist is checked against the destination token account's owner.

## Roles

| Role | Key type | Capability |
| --- | --- | --- |
| `admin` (DEFAULT_ADMIN) | Cold | Rotate role authorities, revoke `MINT_ROLE` (close minter + allowlist PDAs). |
| `MINT_ROLE` | Hot | `mint_tokens` up to the configured rate limit. Granted *implicitly* by `configure_minter` creating the per-(mint, minter) config PDA. |
| `rate_limit_authority` | Cold | `configure_minter` (set or update limit + interval; also doubles as the role grant). |
| `allowlist_authority` | Cold | `add_allowed_mint_recipient` / `remove_allowed_mint_recipient`. |
| global `admin` | Cold | Emergency pause/unpause (`set_paused`) via the program-wide `GlobalConfig` PDA. |

## Instructions

| Function | Caller | Purpose |
| --- | --- | --- |
| `initialize_global` | payer | Create the program-wide singleton (must run once post-deploy before any mint). Initial admin is hardcoded at compile time. |
| `set_paused` | global `admin` | Halt or resume all `mint_tokens` calls program-wide. |
| `update_global_admin` | global `admin` | Rotate the global pause authority. |
| `initialize` | global `admin` | Create the per-mint roles PDA. Run before handing the mint authority to the `mint_authority` PDA. |
| `update_admin` | `admin` | Rotate the admin key. |
| `update_rate_limit_authority` | `admin` | Rotate the rate-limit authority key. |
| `update_allowlist_authority` | `admin` | Rotate the allowlist authority key. |
| `configure_minter` | `rate_limit_authority` | Create or update a `(mint, minter)` rate-limit config, and create the allowlist PDA on first call. Preserves remaining capacity on reconfigure; also grants `MINT_ROLE`. |
| `revoke_minter` | `admin` | Close a `(mint, minter)` config and its allowlist PDA. Revokes `MINT_ROLE`, returns rent. |
| `add_allowed_mint_recipient` | `allowlist_authority` | Add `recipient` to the `(mint, minter)` allowlist. |
| `remove_allowed_mint_recipient` | `allowlist_authority` | Remove `recipient` from the allowlist. |
| `mint_tokens` | `minter` (signer) | Rate-limited mint to a whitelisted recipient (mirrors SPL `mint_to` accounts: mint, destination token account, authority). Requires `GlobalConfig` to be unpaused. |

## PDAs

All PDAs live under this program's ID; seeds are constants in
[`programs/mint-controller/src/constants.rs`](programs/mint-controller/src/constants.rs).

| PDA | Seeds | Purpose |
| --- | --- | --- |
| `GlobalConfig` | `[b"global_config"]` | Program-wide emergency pause flag and global admin. |
| `MintRoles` | `[b"mint_roles", mint]` | Holds `admin`, `rate_limit_authority`, `allowlist_authority`. |
| `MintAuthority` | `[b"mint_authority", mint]` | Empty marker PDA whose address is the SPL mint authority and signs `mint_to` CPIs. |
| `MintRateLimitConfig` | `[b"mint_rate_limit_config", mint, minter]` | Per-(mint, minter) rate-limit state. Existence == `MINT_ROLE` granted. |
| `MintAllowlistConfig` | `[b"mint_allowlist_config", mint, minter]` | Per-(mint, minter) allowlist (capped at `MAX_ALLOWLIST_LEN = 100`). |

### Rent

`rate_limit_authority` pays the rent for both minter PDAs, about 0.0247 SOL each time, and
`revoke_minter` returns it to `admin`. So rent moves between the two keys on every
grant/revoke cycle, and the refund goes to whoever holds the admin role at close time, not
to the original payer. Fund both keys.

## Operational pre-flight

Configure everything first, then hand the mint authority over last. The handoff is
irreversible: only the current authority can sign `SetAuthority`, and this program
exposes no way to give it back. Anything that goes wrong before the handoff leaves
the mint recoverable by its original authority.

**Once per deployment**

1. Deploy, then check the deployed address matches `declare_id!` and record the binary hash.
2. `initialize_global()` — creates the program-wide pause singleton. It is permissionless
   and pins `admin` to the compiled-in `INITIAL_GLOBAL_ADMIN`, so run it straight after
   deploy. A non-localnet build fails to compile while that constant is the placeholder.
3. Prove the global admin can sign, by sending `set_paused(false)` as a no-op.

**Per stablecoin mint**

1. `initialize(admin, rate_limit_authority, allowlist_authority)`, signed by the global admin.
   The mint must be owned by the classic SPL Token program; Token-2022 is not supported.
2. `configure_minter(minter, limit, interval)` for each minter.
3. `add_allowed_mint_recipient(minter, recipient)` for each recipient. The program checks the
   token account's **owner**, so allowlist the wallet address, not its associated token account.
4. Simulate `[SetAuthority, mint_tokens(1)]` as one transaction with `sigVerify: false`. A
   misconfigured controller fails the simulation and names the failing instruction.
5. Hand the authority over. Derive the PDA from the deployed program ID:

   ```
   mint_authority_pda = findProgramAddressSync([b"mint_authority", mint], programId)
   ```

   ```bash
   spl-token authorize <MINT_ADDRESS> mint <MINT_AUTHORITY_PDA>
   ```

6. Mint a small amount through the controller to confirm the path works.

`initialize` no longer requires the PDA to already hold the authority, so steps 1 to 3 run
while the original key still controls the mint. `mint_tokens` enforces the authority, so
minting stays disabled until step 5 lands.

**Recovery**

Keep the program upgradeable, with the upgrade authority on a cold key, and do not freeze
it. Once the authority moves to the PDA, a program upgrade is the only way to change what
can be done with it.

## Build / test

```bash
# Prerequisites: Rust stable, Solana CLI 2.1+, Anchor CLI 0.31.1, Node 18+, yarn.

cd solana
yarn install
anchor build -- --features localnet
anchor test -- --features localnet   # spins up a local validator and runs tests/mint-controller.ts
```

`--features localnet` is required. Without it `INITIAL_GLOBAL_ADMIN` is still the placeholder
and the build fails on purpose, so a release artifact can't ship an unsignable global admin.
Drop the flag once the constant holds a real key.

The committed `mint_controller-keypair.json` and `declare_id!()` are placeholders; real devnet
and mainnet program IDs will be added when the program is first deployed.
