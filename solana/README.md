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
| `admin` (DEFAULT_ADMIN) | Cold (SCM) | Rotate role authorities, manage recipient allowlists (`add_allowed_mint_recipient` / `remove_allowed_mint_recipient`), revoke `MINT_ROLE` (close minter + allowlist PDAs). |
| `MINT_ROLE` | Hot (CCS) | `mint_tokens` up to the configured rate limit. Granted *implicitly* by `configure_minter` creating the per-(mint, minter) config PDA. |
| `rate_limit_authority` | Cold (SCM) | `configure_minter` (set or update limit + interval; also doubles as the role grant). |
| global `admin` | Cold (SCM) | Emergency pause/unpause (`set_paused`) via the program-wide `GlobalConfig` PDA. |

## Instructions

| Function | Caller | Purpose |
| --- | --- | --- |
| `initialize_global` | payer | Create the program-wide singleton (must run once post-deploy before any mint). Initial admin is hardcoded at compile time. |
| `set_paused` | global `admin` | Halt or resume all `mint_tokens` calls program-wide. |
| `update_global_admin` | global `admin` | Rotate the global pause authority. |
| `initialize` | global `admin` | Create per-mint roles PDA. SPL mint authority must already be the program's `mint_authority` PDA. |
| `update_admin` | `admin` | Rotate the admin key. |
| `update_rate_limit_authority` | `admin` | Rotate the rate-limit authority key. |
| `configure_minter` | `rate_limit_authority` | Create or update a `(mint, minter)` rate-limit config (preserves remaining capacity on reconfigure; also grants `MINT_ROLE`). |
| `revoke_minter` | `admin` | Close a `(mint, minter)` config and allowlist PDA if present (revokes `MINT_ROLE`, returns rent). |
| `add_allowed_mint_recipient` | `admin` | Lazily create the `(mint, minter)` allowlist on first call, push `recipient`. |
| `remove_allowed_mint_recipient` | `admin` | Remove `recipient` from the allowlist. |
| `mint_tokens` | `minter` (signer) | Rate-limited mint to a whitelisted recipient (mirrors SPL `mint_to` accounts: mint, destination token account, authority). Requires `GlobalConfig` to be unpaused. |

## PDAs

All PDAs live under this program's ID; seeds are constants in
[`programs/mint-controller/src/constants.rs`](programs/mint-controller/src/constants.rs).

| PDA | Seeds | Purpose |
| --- | --- | --- |
| `GlobalConfig` | `[b"global_config"]` | Program-wide emergency pause flag and global admin. |
| `MintRoles` | `[b"mint_roles", mint]` | Holds `admin`, `rate_limit_authority`. |
| `MintAuthority` | `[b"mint_authority", mint]` | Empty marker PDA whose address is the SPL mint authority and signs `mint_to` CPIs. |
| `MintRateLimitConfig` | `[b"mint_rate_limit_config", mint, minter]` | Per-(mint, minter) rate-limit state. Existence == `MINT_ROLE` granted. |
| `MintAllowlistConfig` | `[b"mint_allowlist_config", mint, minter]` | Per-(mint, minter) allowlist (capped at `MAX_ALLOWLIST_LEN = 100`). |

## Operational pre-flight

**Deploy ordering (run immediately after deploy to avoid frontruns):**

1. `initialize_global()` — creates the program-wide pause singleton (one-time). The initial global admin is hardcoded in `INITIAL_GLOBAL_ADMIN` (`constants.rs`); set this to the real cold (SCM) key before mainnet deploy.
2. For each stablecoin mint: transfer SPL mint authority to the program PDA, then `initialize(admin, rate_limit_authority)` signed by the global admin.

Before calling `initialize` for a new mint, the *current* SPL mint authority must hand the
authority over to the program's `mint_authority` PDA (the program cannot do this itself —
only the current authority can sign `SetAuthority`). The PDA address is deterministic:

```
mint_authority_pda = findProgramAddressSync(
  [b"mint_authority", mint],
  programId,
)
```

Then:

```bash
spl-token authorize <MINT_ADDRESS> mint <MINT_AUTHORITY_PDA>
```

After that, only the global admin may call `initialize(admin, rate_limit_authority)`.

## Build / test

```bash
# Prerequisites: Rust stable, Solana CLI 2.1+, Anchor CLI 0.31.1, Node 18+, yarn.

cd solana
yarn install
anchor build
anchor test -- --features localnet   # spins up a local validator and runs tests/mint-controller.ts
```

The committed `mint_controller-keypair.json` and `declare_id!()` are placeholders; real devnet
and mainnet program IDs will be added when the program is first deployed.
