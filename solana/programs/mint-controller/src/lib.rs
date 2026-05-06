use anchor_lang::prelude::*;
use anchor_lang::solana_program::program_option::COption;
use anchor_spl::token::{self, Mint, MintTo, Token, TokenAccount};

mod constants;
mod errors;
mod state;
mod utils;

use constants::*;
use errors::*;
use state::*;
use utils::*;

declare_id!("AspjtWo7pCJkiigkfvc5gyMmkhGWpniqfbUMooGg58GC");

#[program]
pub mod mint_controller {
    use super::*;

    /// Initialize the per-mint role-holder PDA and mint-authority PDA for `mint`.
    ///
    /// Pre-conditions: the caller has already transferred SPL `mint_authority`
    /// of `mint` to `mint_authority_pda` via `spl-token authorize`. This
    /// instruction asserts that condition; it cannot perform the transfer
    /// itself because the *current* mint authority must sign the SPL call.
    pub fn initialize(
        ctx: Context<Initialize>,
        admin: Pubkey,
        rate_limit_admin: Pubkey,
        allowlist_admin: Pubkey,
    ) -> Result<()> {
        // Done in the handler rather than as an account constraint to keep the
        // forward reference (mint -> mint_authority) out of the account struct.
        require!(
            ctx.accounts.mint.mint_authority == COption::Some(ctx.accounts.mint_authority.key()),
            MintControllerError::InvalidMintAuthority
        );

        let roles = &mut ctx.accounts.roles;
        roles.admin = admin;
        roles.rate_limit_admin = rate_limit_admin;
        roles.allowlist_admin = allowlist_admin;
        roles.bump = ctx.bumps.roles;

        msg!(
            "Initialized mint_controller for mint {}: admin={}, rate_limit_admin={}, allowlist_admin={}",
            ctx.accounts.mint.key(),
            admin,
            rate_limit_admin,
            allowlist_admin,
        );
        Ok(())
    }

    pub fn update_admin(ctx: Context<UpdateAdmin>, new_admin: Pubkey) -> Result<()> {
        let mint_key = ctx.accounts.mint.key();
        ctx.accounts.roles.admin = new_admin;
        msg!("update_admin mint={} new_admin={}", mint_key, new_admin);
        Ok(())
    }

    pub fn update_rate_limit_admin(
        ctx: Context<UpdateRateLimitAdmin>,
        new_rate_limit_admin: Pubkey,
    ) -> Result<()> {
        let mint_key = ctx.accounts.mint.key();
        ctx.accounts.roles.rate_limit_admin = new_rate_limit_admin;
        msg!(
            "update_rate_limit_admin mint={} new_rate_limit_admin={}",
            mint_key,
            new_rate_limit_admin
        );
        Ok(())
    }

    pub fn update_allowlist_admin(
        ctx: Context<UpdateAllowlistAdmin>,
        new_allowlist_admin: Pubkey,
    ) -> Result<()> {
        let mint_key = ctx.accounts.mint.key();
        ctx.accounts.roles.allowlist_admin = new_allowlist_admin;
        msg!(
            "update_allowlist_admin mint={} new_allowlist_admin={}",
            mint_key,
            new_allowlist_admin
        );
        Ok(())
    }

    /// Configure (or re-configure) `minter`'s rate limit for `mint`.
    ///
    /// First call creates the `MintRateLimitConfig` PDA, which simultaneously
    /// grants `MINT_ROLE` to `minter`. Subsequent calls reset both the limit /
    /// interval and the `remaining` counter back to the new `limit` (matches
    /// EVM `RateLimit._configureRateLimit`).
    pub fn configure_minter(
        ctx: Context<ConfigureMinter>,
        minter: Pubkey,
        limit: u64,
        interval: i64,
    ) -> Result<()> {
        require!(
            limit > 0 && interval > 0,
            MintControllerError::InvalidConfig
        );

        let now = Clock::get()?.unix_timestamp;
        let bump = ctx.bumps.config;
        let config = &mut ctx.accounts.config;
        config.minter_public_key = minter;
        config.limit = limit;
        config.interval = interval;
        // Resetting on every call (including reconfigure) is intentional: it
        // matches the EVM behaviour, and means a misconfigured minter can't
        // race in a mint between an `update` and the operator noticing.
        config.remaining = limit;
        config.last_consumed = now;
        config.bump = bump;

        msg!(
            "configure_minter mint={} minter={} limit={} interval={}s",
            ctx.accounts.mint.key(),
            minter,
            limit,
            interval,
        );
        Ok(())
    }

    /// Revoke `MINT_ROLE` from `minter` for `mint` by closing the config PDA.
    ///
    /// Rent is returned to `admin`. After this returns, any in-flight `mint`
    /// instruction for the same (mint, minter) will fail at account
    /// deserialization (`AccountNotInitialized`).
    pub fn revoke_minter(ctx: Context<RevokeMinter>, minter: Pubkey) -> Result<()> {
        msg!(
            "revoke_minter mint={} minter={}",
            ctx.accounts.mint.key(),
            minter,
        );
        Ok(())
    }

    /// Add `address` to `minter`'s recipient allowlist for `mint`.
    ///
    /// Lazily creates the `MintAllowlistConfig` PDA on first call (the
    /// `init_if_needed` constraint on `allowlist`). Subsequent calls reuse the
    /// existing PDA. Rejects if `address` is already present, or if the
    /// allowlist is at `MAX_ALLOWLIST_LEN` capacity.
    pub fn add_to_allowlist(
        ctx: Context<AddToAllowlist>,
        minter: Pubkey,
        address: Pubkey,
    ) -> Result<()> {
        let bump = ctx.bumps.allowlist;
        let allowlist = &mut ctx.accounts.allowlist;

        // `init_if_needed` doesn't run any handler logic when the account
        // already exists, so the bump persists across calls. On the very first
        // call, the freshly-initialized account has bump=0 and we need to set
        // it; on subsequent calls we leave the existing bump alone.
        if allowlist.bump == 0 {
            allowlist.bump = bump;
        }

        require!(
            !allowlist.addresses.contains(&address),
            MintControllerError::AddressAlreadyAllowlisted
        );
        require!(
            allowlist.addresses.len() < MAX_ALLOWLIST_LEN,
            MintControllerError::MaxAllowlistLenReached
        );

        allowlist.addresses.push(address);

        msg!(
            "add_to_allowlist mint={} minter={} address={} (now {} entries)",
            ctx.accounts.mint.key(),
            minter,
            address,
            allowlist.addresses.len(),
        );
        Ok(())
    }

    /// Remove `address` from `minter`'s recipient allowlist for `mint`.
    ///
    /// Errors with `AccountNotInitialized` if no allowlist has been created
    /// yet for this (mint, minter) — there's no "remove from empty" path
    /// because that would require silently creating the PDA.
    pub fn remove_from_allowlist(
        ctx: Context<RemoveFromAllowlist>,
        minter: Pubkey,
        address: Pubkey,
    ) -> Result<()> {
        let allowlist = &mut ctx.accounts.allowlist;
        let position = allowlist
            .addresses
            .iter()
            .position(|a| a == &address)
            .ok_or(MintControllerError::AddressNotAllowlisted)?;

        // swap_remove is O(1); ordering of the allowlist is not part of the
        // contract surface (no callers rely on iteration order).
        allowlist.addresses.swap_remove(position);

        msg!(
            "remove_from_allowlist mint={} minter={} address={} (now {} entries)",
            ctx.accounts.mint.key(),
            minter,
            address,
            allowlist.addresses.len(),
        );
        Ok(())
    }

    /// Rate-limited mint to a whitelisted recipient.
    ///
    /// Pre-flight checks (in order):
    ///   1. `minter` signer matches the on-chain `config.minter_public_key`.
    ///   2. `recipient` is in `allowlist.addresses`.
    ///   3. `amount` does not exceed the minter's currently-available capacity.
    /// On success: updates rate-limit accounting and CPIs `mint_to` signed by
    /// the per-mint `mint_authority` PDA.
    pub fn mint_tokens(ctx: Context<MintTokens>, amount: u64) -> Result<()> {
        require!(amount > 0, MintControllerError::InvalidAmount);
        require!(
            ctx.accounts
                .allowlist
                .is_allowlisted(&ctx.accounts.recipient.key()),
            MintControllerError::RecipientNotAllowlisted
        );

        let now = Clock::get()?.unix_timestamp;
        consume_capacity(&mut ctx.accounts.config, amount, now)?;

        let mint_key = ctx.accounts.mint.key();
        let bump = ctx.bumps.mint_authority;
        let signer_seeds: &[&[u8]] = &[MINT_AUTHORITY_SEED, mint_key.as_ref(), &[bump]];

        token::mint_to(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                MintTo {
                    mint: ctx.accounts.mint.to_account_info(),
                    to: ctx.accounts.recipient_token_account.to_account_info(),
                    authority: ctx.accounts.mint_authority.to_account_info(),
                },
                &[signer_seeds],
            ),
            amount,
        )?;

        msg!(
            "mint mint={} minter={} recipient={} amount={} remaining={}",
            mint_key,
            ctx.accounts.minter.key(),
            ctx.accounts.recipient.key(),
            amount,
            ctx.accounts.config.remaining,
        );
        Ok(())
    }
}

/* ------------------------------------------------------------------------- */
/*                              Accounts contexts                            */
/* ------------------------------------------------------------------------- */

#[derive(Accounts)]
pub struct Initialize<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        init,
        payer = payer,
        space = 8 + MintRoles::INIT_SPACE,
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump,
    )]
    pub roles: Account<'info, MintRoles>,

    /// CHECK: PDA whose address is the SPL mint authority. Holds no state of
    /// its own — its only purpose is to be a deterministic signer for
    /// `mint_to` CPIs.
    #[account(seeds = [MINT_AUTHORITY_SEED, mint.key().as_ref()], bump)]
    pub mint_authority: UncheckedAccount<'info>,

    #[account(mut)]
    pub payer: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateAdmin<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump = roles.bump,
        has_one = admin @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    pub admin: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateRateLimitAdmin<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump = roles.bump,
        has_one = admin @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    pub admin: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateAllowlistAdmin<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump = roles.bump,
        has_one = admin @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    pub admin: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(minter: Pubkey)]
pub struct ConfigureMinter<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump = roles.bump,
        has_one = rate_limit_admin @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    #[account(
        init_if_needed,
        payer = rate_limit_admin,
        space = 8 + MintRateLimitConfig::INIT_SPACE,
        seeds = [MINT_RATE_LIMIT_CONFIG_SEED, mint.key().as_ref(), minter.as_ref()],
        bump,
    )]
    pub config: Account<'info, MintRateLimitConfig>,

    #[account(mut)]
    pub rate_limit_admin: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(minter: Pubkey)]
pub struct RevokeMinter<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump = roles.bump,
        has_one = admin @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    /// Closing returns rent to `admin`. We also defensively check the stored
    /// `minter_public_key` so that an admin who passes a wrong `minter` arg
    /// (and therefore a wrong PDA) is caught instead of silently closing
    /// the wrong config.
    #[account(
        mut,
        close = admin,
        seeds = [MINT_RATE_LIMIT_CONFIG_SEED, mint.key().as_ref(), minter.as_ref()],
        bump = config.bump,
        constraint = config.minter_public_key == minter @ MintControllerError::MinterMismatch,
    )]
    pub config: Account<'info, MintRateLimitConfig>,

    #[account(mut)]
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(minter: Pubkey)]
pub struct AddToAllowlist<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump = roles.bump,
        has_one = allowlist_admin @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    #[account(
        init_if_needed,
        payer = allowlist_admin,
        space = 8 + MintAllowlistConfig::INIT_SPACE,
        seeds = [MINT_ALLOWLIST_CONFIG_SEED, mint.key().as_ref(), minter.as_ref()],
        bump,
    )]
    pub allowlist: Account<'info, MintAllowlistConfig>,

    #[account(mut)]
    pub allowlist_admin: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(minter: Pubkey)]
pub struct RemoveFromAllowlist<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump = roles.bump,
        has_one = allowlist_admin @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    #[account(
        mut,
        seeds = [MINT_ALLOWLIST_CONFIG_SEED, mint.key().as_ref(), minter.as_ref()],
        bump = allowlist.bump,
    )]
    pub allowlist: Account<'info, MintAllowlistConfig>,

    pub allowlist_admin: Signer<'info>,
}

#[derive(Accounts)]
pub struct MintTokens<'info> {
    /// MINT_ROLE-holding caller. Identifies which (mint, minter) config and
    /// allowlist to load via PDA seeds.
    pub minter: Signer<'info>,

    #[account(
        mut,
        seeds = [MINT_RATE_LIMIT_CONFIG_SEED, mint.key().as_ref(), minter.key().as_ref()],
        bump = config.bump,
        constraint = config.minter_public_key == minter.key()
            @ MintControllerError::MinterMismatch,
    )]
    pub config: Account<'info, MintRateLimitConfig>,

    #[account(
        seeds = [MINT_ALLOWLIST_CONFIG_SEED, mint.key().as_ref(), minter.key().as_ref()],
        bump = allowlist.bump,
    )]
    pub allowlist: Account<'info, MintAllowlistConfig>,

    /// Mutable because `mint_to` increases supply. The constraint verifies
    /// that this program's `mint_authority` PDA owns the SPL mint authority.
    #[account(
        mut,
        constraint = mint.mint_authority == COption::Some(mint_authority.key())
            @ MintControllerError::InvalidMintAuthority,
    )]
    pub mint: Account<'info, Mint>,

    /// CHECK: PDA whose address is the SPL mint authority; signs `mint_to` via seeds.
    #[account(seeds = [MINT_AUTHORITY_SEED, mint.key().as_ref()], bump)]
    pub mint_authority: UncheckedAccount<'info>,

    /// The recipient's token account. `token::authority = recipient` prevents
    /// passing a whitelisted recipient but routing tokens to a different owner.
    #[account(mut, token::mint = mint, token::authority = recipient)]
    pub recipient_token_account: Account<'info, TokenAccount>,

    /// CHECK: not a signer — anyone can trigger a mint on behalf of a
    /// whitelisted recipient. Validated against the allowlist in the handler.
    pub recipient: UncheckedAccount<'info>,

    /// Transaction fee payer. Distinct from `minter` so that a hot mint key
    /// can hold zero SOL — typical operational pattern where a relayer pays gas.
    #[account(mut)]
    pub payer: Signer<'info>,

    pub token_program: Program<'info, Token>,
}
