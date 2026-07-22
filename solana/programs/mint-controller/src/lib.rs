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

    /// Initialize the program-wide singleton (emergency pause authority).
    ///
    /// Must be called once post-deploy before any `mint_tokens` can succeed.
    /// The `init` constraint prevents re-initialization. The initial admin is
    /// hardcoded at compile time so a frontrun cannot set a different admin.
    pub fn initialize_global(ctx: Context<InitializeGlobal>) -> Result<()> {
        let global_config = &mut ctx.accounts.global_config;
        global_config.admin = INITIAL_GLOBAL_ADMIN;
        global_config.paused = false;
        global_config.bump = ctx.bumps.global_config;

        msg!("initialize_global admin={}", INITIAL_GLOBAL_ADMIN);
        Ok(())
    }

    pub fn set_paused(ctx: Context<SetPaused>, paused: bool) -> Result<()> {
        ctx.accounts.global_config.paused = paused;
        msg!("set_paused paused={}", paused);
        Ok(())
    }

    pub fn update_global_admin(ctx: Context<UpdateGlobalAdmin>, new_admin: Pubkey) -> Result<()> {
        require_keys_neq!(new_admin, Pubkey::default(), MintControllerError::InvalidAddress);
        ctx.accounts.global_config.admin = new_admin;
        msg!("update_global_admin new_admin={}", new_admin);
        Ok(())
    }

    /// Initialize the per-mint role-holder PDA and mint-authority PDA for `mint`.
    ///
    /// The `init` constraint on `roles` prevents re-initialization. Only the
    /// global admin may call this instruction.
    pub fn initialize(
        ctx: Context<Initialize>,
        admin: Pubkey,
        rate_limit_authority: Pubkey,
        allowlist_authority: Pubkey,
    ) -> Result<()> {
        require_keys_eq!(
            ctx.accounts.global_config.admin,
            ctx.accounts.global_admin.key(),
            MintControllerError::Unauthorized
        );

        require_keys_neq!(admin, Pubkey::default(), MintControllerError::InvalidAddress);
        require_keys_neq!(
            rate_limit_authority,
            Pubkey::default(),
            MintControllerError::InvalidAddress
        );
        require_keys_neq!(
            allowlist_authority,
            Pubkey::default(),
            MintControllerError::InvalidAddress
        );

        // Done in the handler rather than as an account constraint to keep the
        // forward reference (mint -> mint_authority) out of the account struct.
        require!(
            ctx.accounts.mint.mint_authority == COption::Some(ctx.accounts.mint_authority.key()),
            MintControllerError::InvalidMintAuthority
        );

        let roles = &mut ctx.accounts.roles;
        roles.admin = admin;
        roles.rate_limit_authority = rate_limit_authority;
        roles.allowlist_authority = allowlist_authority;
        roles.bump = ctx.bumps.roles;

        msg!(
            "Initialized mint_controller for mint {}: admin={}, rate_limit_authority={}, allowlist_authority={}",
            ctx.accounts.mint.key(),
            admin,
            rate_limit_authority,
            allowlist_authority,
        );
        Ok(())
    }

    pub fn update_admin(ctx: Context<UpdateAdmin>, new_admin: Pubkey) -> Result<()> {
        require_keys_neq!(new_admin, Pubkey::default(), MintControllerError::InvalidAddress);
        let mint_key = ctx.accounts.mint.key();
        ctx.accounts.roles.admin = new_admin;
        msg!("update_admin mint={} new_admin={}", mint_key, new_admin);
        Ok(())
    }

    pub fn update_rate_limit_authority(
        ctx: Context<UpdateRateLimitAuthority>,
        new_rate_limit_authority: Pubkey,
    ) -> Result<()> {
        require_keys_neq!(
            new_rate_limit_authority,
            Pubkey::default(),
            MintControllerError::InvalidAddress
        );
        let mint_key = ctx.accounts.mint.key();
        ctx.accounts.roles.rate_limit_authority = new_rate_limit_authority;
        msg!(
            "update_rate_limit_authority mint={} new_rate_limit_authority={}",
            mint_key,
            new_rate_limit_authority
        );
        Ok(())
    }

    pub fn update_allowlist_authority(
        ctx: Context<UpdateAllowlistAuthority>,
        new_allowlist_authority: Pubkey,
    ) -> Result<()> {
        require_keys_neq!(
            new_allowlist_authority,
            Pubkey::default(),
            MintControllerError::InvalidAddress
        );
        let mint_key = ctx.accounts.mint.key();
        ctx.accounts.roles.allowlist_authority = new_allowlist_authority;
        msg!(
            "update_allowlist_authority mint={} new_allowlist_authority={}",
            mint_key,
            new_allowlist_authority
        );
        Ok(())
    }

    /// Configure (or re-configure) `minter`'s rate limit for `mint`. The first
    /// call also creates the (initially empty) allowlist PDA for the minter.
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
        require_keys_neq!(minter, Pubkey::default(), MintControllerError::InvalidAddress);

        let bump = ctx.bumps.config;
        let config = &mut ctx.accounts.config;

        if !config.is_initialized {
            // Fresh init.
            let now = Clock::get()?.unix_timestamp;
            config.minter_public_key = minter;
            config.remaining = limit;
            config.last_consumed = now;
            config.bump = bump;
            config.is_initialized = true;
        } else {
            // Reconfigure: defensive minter check; seed already ties them.
            require_keys_eq!(
                config.minter_public_key,
                minter,
                MintControllerError::MinterMismatch
            );
            // Snapshot available capacity and restart the window so a shorter
            // interval can't retroactively refresh. Cap at the new limit.
            let now = Clock::get()?.unix_timestamp;
            config.remaining = current_capacity(config, now)?.min(limit);
            config.last_consumed = now;
        }

        config.limit = limit;
        config.interval = interval;

        // Allowlist PDA is created via `init_if_needed`; stamp its canonical bump.
        ctx.accounts.allowlist.bump = ctx.bumps.allowlist;

        msg!(
            "configure_minter mint={} minter={} limit={} interval={}s",
            ctx.accounts.mint.key(),
            minter,
            limit,
            interval,
        );
        Ok(())
    }

    /// Revoke `MINT_ROLE` from `minter` for `mint` by closing both the config
    /// and allowlist PDAs (rent returned to `admin`).
    pub fn revoke_minter(ctx: Context<RevokeMinter>, minter: Pubkey) -> Result<()> {
        msg!(
            "revoke_minter mint={} minter={}",
            ctx.accounts.mint.key(),
            minter,
        );
        Ok(())
    }

    /// Add `recipient` to `minter`'s recipient allowlist for `mint`.
    ///
    /// `recipient` is the token account *owner*; that the destination is a real
    /// token account for this mint is enforced at mint time in `MintTokens`.
    pub fn add_allowed_mint_recipient(
        ctx: Context<AddAllowedMintRecipient>,
        minter: Pubkey,
        recipient: Pubkey,
    ) -> Result<()> {
        require_keys_neq!(recipient, Pubkey::default(), MintControllerError::InvalidAddress);

        let allowlist = &mut ctx.accounts.allowlist;
        require!(
            !allowlist.addresses.contains(&recipient),
            MintControllerError::AddressAlreadyAllowlisted
        );
        require!(
            allowlist.addresses.len() < MAX_ALLOWLIST_LEN,
            MintControllerError::MaxAllowlistLenReached
        );

        allowlist.addresses.push(recipient);

        msg!(
            "add_allowed_mint_recipient mint={} minter={} recipient={} (now {} entries)",
            ctx.accounts.mint.key(),
            minter,
            recipient,
            allowlist.addresses.len(),
        );
        Ok(())
    }

    /// Remove `recipient` from `minter`'s recipient allowlist for `mint`.
    pub fn remove_allowed_mint_recipient(
        ctx: Context<RemoveAllowedMintRecipient>,
        minter: Pubkey,
        recipient: Pubkey,
    ) -> Result<()> {
        let allowlist = &mut ctx.accounts.allowlist;
        let position = allowlist
            .addresses
            .iter()
            .position(|a| a == &recipient)
            .ok_or(MintControllerError::AddressNotAllowlisted)?;

        // swap_remove is O(1); ordering of the allowlist is not part of the
        // contract surface (no callers rely on iteration order).
        allowlist.addresses.swap_remove(position);

        msg!(
            "remove_allowed_mint_recipient mint={} minter={} recipient={} (now {} entries)",
            ctx.accounts.mint.key(),
            minter,
            recipient,
            allowlist.addresses.len(),
        );
        Ok(())
    }

    /// Rate-limited mint to a whitelisted recipient.
    pub fn mint_tokens(ctx: Context<MintTokens>, amount: u64) -> Result<()> {
        require!(
            !ctx.accounts.global_config.paused,
            MintControllerError::MintingPaused
        );
        require!(amount > 0, MintControllerError::InvalidAmount);
        require!(
            ctx.accounts
                .allowlist
                .is_allowlisted(&ctx.accounts.recipient_token_account.owner),
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
            ctx.accounts.recipient_token_account.owner,
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
pub struct InitializeGlobal<'info> {
    #[account(
        init,
        payer = payer,
        space = 8 + GlobalConfig::INIT_SPACE,
        seeds = [GLOBAL_CONFIG_SEED],
        bump,
    )]
    pub global_config: Account<'info, GlobalConfig>,

    #[account(mut)]
    pub payer: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetPaused<'info> {
    #[account(
        mut,
        seeds = [GLOBAL_CONFIG_SEED],
        bump = global_config.bump,
        has_one = admin @ MintControllerError::Unauthorized,
    )]
    pub global_config: Account<'info, GlobalConfig>,

    pub admin: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateGlobalAdmin<'info> {
    #[account(
        mut,
        seeds = [GLOBAL_CONFIG_SEED],
        bump = global_config.bump,
        has_one = admin @ MintControllerError::Unauthorized,
    )]
    pub global_config: Account<'info, GlobalConfig>,

    pub admin: Signer<'info>,
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        seeds = [GLOBAL_CONFIG_SEED],
        bump = global_config.bump,
    )]
    pub global_config: Account<'info, GlobalConfig>,

    pub global_admin: Signer<'info>,

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
pub struct UpdateRateLimitAuthority<'info> {
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
pub struct UpdateAllowlistAuthority<'info> {
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
        has_one = rate_limit_authority @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    #[account(
        init_if_needed,
        payer = rate_limit_authority,
        space = 8 + MintRateLimitConfig::INIT_SPACE,
        seeds = [MINT_RATE_LIMIT_CONFIG_SEED, mint.key().as_ref(), minter.as_ref()],
        bump,
    )]
    pub config: Account<'info, MintRateLimitConfig>,

    /// Allowlist PDA created alongside the rate-limit config so it always exists
    /// for the lifetime of the minter and is always closed on revoke.
    #[account(
        init_if_needed,
        payer = rate_limit_authority,
        space = 8 + MintAllowlistConfig::INIT_SPACE,
        seeds = [MINT_ALLOWLIST_CONFIG_SEED, mint.key().as_ref(), minter.as_ref()],
        bump,
    )]
    pub allowlist: Account<'info, MintAllowlistConfig>,

    #[account(mut)]
    pub rate_limit_authority: Signer<'info>,

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

    /// Always exists (created in `configure_minter`); closed here, rent to `admin`.
    #[account(
        mut,
        close = admin,
        seeds = [MINT_ALLOWLIST_CONFIG_SEED, mint.key().as_ref(), minter.as_ref()],
        bump = allowlist.bump,
    )]
    pub allowlist: Account<'info, MintAllowlistConfig>,

    #[account(mut)]
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(minter: Pubkey)]
pub struct AddAllowedMintRecipient<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump = roles.bump,
        has_one = allowlist_authority @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    #[account(
        mut,
        seeds = [MINT_ALLOWLIST_CONFIG_SEED, mint.key().as_ref(), minter.as_ref()],
        bump = allowlist.bump,
    )]
    pub allowlist: Account<'info, MintAllowlistConfig>,

    pub allowlist_authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(minter: Pubkey)]
pub struct RemoveAllowedMintRecipient<'info> {
    pub mint: Account<'info, Mint>,

    #[account(
        seeds = [MINT_ROLES_SEED, mint.key().as_ref()],
        bump = roles.bump,
        has_one = allowlist_authority @ MintControllerError::Unauthorized,
    )]
    pub roles: Account<'info, MintRoles>,

    #[account(
        mut,
        seeds = [MINT_ALLOWLIST_CONFIG_SEED, mint.key().as_ref(), minter.as_ref()],
        bump = allowlist.bump,
    )]
    pub allowlist: Account<'info, MintAllowlistConfig>,

    pub allowlist_authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct MintTokens<'info> {
    /// MINT_ROLE-holding caller. Identifies which (mint, minter) config and
    /// allowlist to load via PDA seeds.
    pub minter: Signer<'info>,

    #[account(
        seeds = [GLOBAL_CONFIG_SEED],
        bump = global_config.bump,
    )]
    pub global_config: Account<'info, GlobalConfig>,

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

    /// Destination token account (typed + `token::mint = mint`); the allowlist
    /// is checked against its `owner`.
    #[account(mut, token::mint = mint)]
    pub recipient_token_account: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
}
