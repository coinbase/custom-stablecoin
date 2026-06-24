/// PDA seeds.
///
/// The seed strings are part of the on-chain layout: changing any of them is a
/// breaking change that would orphan every existing PDA. Treat them as constants.

/// Seed for the program-wide singleton PDA: holds the emergency pause flag.
pub const GLOBAL_CONFIG_SEED: &[u8] = b"global_config";

/// Seed for the per-mint roles PDA: holds admin / rate_limit_authority.
pub const MINT_ROLES_SEED: &[u8] = b"mint_roles";

/// Seed for the per-mint mint-authority PDA. The PDA itself holds no state; its
/// address is set as the SPL mint's `mint_authority` and signs `mint_to` CPIs.
pub const MINT_AUTHORITY_SEED: &[u8] = b"mint_authority";

/// Seed for the per-(mint, minter) rate-limit configuration PDA. The existence of
/// this PDA is what grants `MINT_ROLE` to a given minter for a given mint.
pub const MINT_RATE_LIMIT_CONFIG_SEED: &[u8] = b"mint_rate_limit_config";

/// Seed for the per-(mint, minter) allowlist PDA.
pub const MINT_ALLOWLIST_CONFIG_SEED: &[u8] = b"mint_allowlist_config";

/// Maximum number of recipient addresses a single (mint, minter) allowlist may hold.
///
/// Picked conservatively — the per-(mint, minter) allowlist account is sized for
/// `4 + 32 * MAX_ALLOWLIST_LEN` bytes plus 1 byte for `bump`. At 100 entries the
/// allowlist account is ~3.2 KiB, well below the 10 KiB single-account hard cap.
/// Operators can raise this in a future migration if needed.
pub const MAX_ALLOWLIST_LEN: usize = 100;
