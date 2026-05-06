use crate::errors::MintControllerError;
use crate::state::MintRateLimitConfig;
use anchor_lang::prelude::*;

/// Returns the minter's currently-available mint capacity at `now`.
///
/// Mirrors the EVM `RateLimit.currentLimit` exactly: capacity replenishes
/// linearly at a rate of `limit` per `interval`, and is capped at `limit`.
///
/// Done in `u128` so that intermediate `elapsed * limit` cannot overflow even
/// for a `limit` near `u64::MAX` and very large elapsed time.
pub fn current_capacity(config: &MintRateLimitConfig, now: i64) -> Result<u64> {
    require!(config.interval > 0, MintControllerError::InvalidConfig);

    let elapsed = now.saturating_sub(config.last_consumed).max(0) as u128;
    let limit = config.limit as u128;
    let interval = config.interval as u128;

    let replenishment = elapsed
        .checked_mul(limit)
        .ok_or(MintControllerError::Overflow)?
        .checked_div(interval)
        .ok_or(MintControllerError::Overflow)?;

    let current = (config.remaining as u128)
        .saturating_add(replenishment)
        .min(limit);

    // current <= limit which fits in u64 because `limit` is u64, so this cast is safe.
    Ok(current as u64)
}

/// Deducts `amount` from `config`'s capacity, replenishing first.
///
/// Reverts with `LimitExceeded` if `amount` exceeds currently available capacity.
/// Updates `remaining` to (capacity - amount) and `last_consumed` to `now`.
pub fn consume_capacity(config: &mut MintRateLimitConfig, amount: u64, now: i64) -> Result<()> {
    let capacity = current_capacity(config, now)?;
    require!(amount <= capacity, MintControllerError::LimitExceeded);

    // Safe: amount <= capacity is enforced above.
    config.remaining = capacity - amount;
    config.last_consumed = now;
    Ok(())
}
