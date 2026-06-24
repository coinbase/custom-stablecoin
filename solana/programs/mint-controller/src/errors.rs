use anchor_lang::prelude::*;

#[error_code]
pub enum MintControllerError {
    #[msg("Caller is not authorized for this role")]
    Unauthorized,
    #[msg("Provided minter does not match the on-chain rate-limit config")]
    MinterMismatch,
    #[msg("SPL mint authority does not match the program's mint_authority PDA")]
    InvalidMintAuthority,
    #[msg("Limit and interval must both be non-zero")]
    InvalidConfig,
    #[msg("Mint amount exceeds the minter's currently available rate-limit capacity")]
    LimitExceeded,
    #[msg("Recipient is not on the minter's allowlist")]
    RecipientNotAllowlisted,
    #[msg("Allowlist already contains this address")]
    AddressAlreadyAllowlisted,
    #[msg("Address not found in the allowlist")]
    AddressNotAllowlisted,
    #[msg("Maximum allowlist length reached")]
    MaxAllowlistLenReached,
    #[msg("Arithmetic overflow")]
    Overflow,
    #[msg("Mint amount must be greater than zero")]
    InvalidAmount,
    #[msg("All minting is paused")]
    MintingPaused,
}
