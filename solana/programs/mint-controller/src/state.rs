use crate::constants::MAX_ALLOWLIST_LEN;
use anchor_lang::prelude::*;

// Discriminator-stability invariant: Anchor derives the 8-byte account
// discriminator from the *struct name*. Renaming any of the structs below would
// break re-deserialization of every existing on-chain PDA. Field order /
// reordering does not affect the discriminator but does break borsh layout, so
// treat the field order as part of the on-chain layout too.

/// Per-mint role-holder PDA. There is exactly one of these per SPL mint.
///
/// `MINT_ROLE` (the right to call `mint_tokens`) is *not* stored here: it is
/// implicitly granted by the existence of a `MintRateLimitConfig` PDA at
/// `[MINT_RATE_LIMIT_CONFIG_SEED, mint, minter]`. Granting a minter is done by
/// `configure_minter`; revoking is done by `revoke_minter` (which closes the
/// PDA). This collapses the EVM "grant role then configure" two-step into a
/// single atomic instruction.
#[account]
#[derive(InitSpace)]
pub struct MintRoles {
    /// Cold key (SCM) that can rotate role authorities, manage recipient
    /// allowlists, and revoke minters.
    pub admin: Pubkey,
    /// Cold key (SCM) that can configure / reconfigure rate limits for minters.
    pub rate_limit_authority: Pubkey,
    pub bump: u8,
}

/// Per-(mint, minter) rate-limit configuration PDA.
///
/// Existence of this PDA at `[MINT_RATE_LIMIT_CONFIG_SEED, mint, minter]` is
/// what grants `minter` the `MINT_ROLE` for `mint`. `revoke_minter` closes the
/// PDA to revoke the role and reclaim rent.
///
/// Capacity replenishes linearly: see `utils::current_capacity` for the math
/// (mirrors the EVM `RateLimit.sol`).
#[account]
#[derive(InitSpace)]
pub struct MintRateLimitConfig {
    /// The minter pubkey this config grants `MINT_ROLE` to. Stored
    /// redundantly with the seed so that `MintTokens` can defensively assert
    /// `config.minter_public_key == minter.key()` even if a future Anchor
    /// upgrade weakens seed verification.
    pub minter_public_key: Pubkey,
    /// Maximum mint capacity the minter can accumulate.
    pub limit: u64,
    /// Replenishment interval in seconds.
    pub interval: i64,
    /// Unix timestamp of the most recent successful mint. The replenishment
    /// anchor; any `current_capacity` query is computed relative to this.
    pub last_consumed: i64,
    /// Remaining capacity *as of `last_consumed`*. Effective current capacity
    /// is `min(remaining + (now - last_consumed) * limit / interval, limit)`.
    pub remaining: u64,
    pub bump: u8,
}

/// Per-(mint, minter) allowlist PDA. Lazily created on the first
/// `add_allowed_mint_recipient` call (see the instruction's `init_if_needed` constraint).
///
/// Held intentionally separate from `MintRateLimitConfig` so the account size
/// can grow independently if `MAX_ALLOWLIST_LEN` is raised later.
#[account]
#[derive(InitSpace)]
pub struct MintAllowlistConfig {
    #[max_len(MAX_ALLOWLIST_LEN)]
    pub addresses: Vec<Pubkey>,
    pub bump: u8,
}

impl MintAllowlistConfig {
    /// Whether `address` is permitted to receive mints from this (mint, minter).
    pub fn is_allowlisted(&self, address: &Pubkey) -> bool {
        self.addresses.contains(address)
    }
}
