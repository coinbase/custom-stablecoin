// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {Blocklist} from "./lib/Blocklist.sol";
import {ERC3009Upgradeable} from "./lib/ERC3009Upgradeable.sol";
import {MintRateLimit} from "./lib/MintRateLimit.sol";
import {TokenMetadata} from "./lib/TokenMetadata.sol";

/// @title Stablecoin
/// @notice Stablecoin implementation, upgradeable via a beacon proxy.
///
/// @dev Roles:
///   - DEFAULT_ADMIN_ROLE – can grant/revoke all other roles. Two-step
///     transfer with configurable delay. Can atomically grant MINT_ROLE and
///     configure a rate limit via {grantMinterRoleWithLimit}.
///   - MINT_ROLE – can mint tokens up to their configured rate limit.
///     After granting, a MINT_RATE_LIMIT_ROLE holder must call {configureMinter}
///     to set the rate limit. Revoking MINT_ROLE clears the rate limit.
///   - MINT_RATE_LIMIT_ROLE – can update rate limits for existing minters.
///   - BURN_ROLE – can burn their own tokens.
///   - PAUSE_ROLE – can pause/unpause all transfers.
///   - BLOCKLIST_ROLE – can update blocklist status for addresses.
///   - METADATA_ROLE – can update the contract-level metadata URI (ERC-7572).
/// @author Coinbase
contract Stablecoin is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    ERC20PermitUpgradeable,
    ERC3009Upgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    Blocklist,
    MintRateLimit,
    TokenMetadata
{
    /// @notice Role required to mint tokens up to the configured rate limit.
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");

    /// @notice Role required to burn the caller's own tokens.
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");

    /// @notice Role required to update mint rate-limit configurations for existing minters.
    bytes32 public constant MINT_RATE_LIMIT_ROLE = keccak256("MINT_RATE_LIMIT_ROLE");

    /// @notice Role required to update blocklist status for addresses.
    bytes32 public constant BLOCKLIST_ROLE = keccak256("BLOCKLIST_ROLE");

    /// @notice Role required to update the contract-level metadata URI (ERC-7572).
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");

    /// @notice Role required to pause and unpause all token transfers.
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    /// @notice The version of the stablecoin implementation.
    string public constant VERSION = "1.0.0";

    /// @notice Emitted when tokens are minted.
    ///
    /// @param minter The address that performed the mint.
    /// @param to     The recipient of the minted tokens.
    /// @param amount The number of tokens minted.
    event Minted(address indexed minter, address indexed to, uint256 amount);

    /// @notice Emitted when tokens are burned.
    ///
    /// @param burner The address that burned tokens.
    /// @param amount The number of tokens burned.
    event Burned(address indexed burner, uint256 amount);

    /// @notice Emitted when a memo is attached to a mint, burn, or transfer.
    ///
    /// @param memo The memo that was attached.
    event Memo(bytes32 indexed memo);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Disables initializers on the implementation contract to prevent direct initialization.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the stablecoin with the given name, symbol, decimals, and admin.
    ///
    /// @param name          Token name.
    /// @param symbol        Token symbol.
    /// @param decimals_     Token decimal places (max 18).
    /// @param admin         The initial default admin address.
    function initialize(string calldata name, string calldata symbol, uint8 decimals_, address admin)
        external
        initializer
    {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        _initializeDecimals({value: decimals_});
        __AccessControlDefaultAdminRules_init({initialDefaultAdmin: admin, initialDelay: 0});
        __ERC20Pausable_init();
    }

    /// @notice Transfers `amount` tokens from the caller to `to` with a memo.
    ///
    /// @param to     Recipient address.
    /// @param amount Number of tokens to transfer.
    /// @param memo   The memo associated with the transfer.
    function transferWithMemo(address to, uint256 amount, bytes32 memo) external {
        _transfer({from: msg.sender, to: to, value: amount});
        emit Memo({memo: memo});
    }

    /// @notice Transfers `amount` tokens from `from` to `to` with a memo.
    ///
    /// @param from   Sender address.
    /// @param to     Recipient address.
    /// @param amount Number of tokens to transfer.
    /// @param memo   The memo associated with the transfer.
    function transferFromWithMemo(address from, address to, uint256 amount, bytes32 memo) external {
        _spendAllowance({owner: from, spender: msg.sender, value: amount});
        _transfer({from: from, to: to, value: amount});
        emit Memo({memo: memo});
    }

    /// @notice Mints `amount` tokens to `to`.
    ///
    /// @param to     Recipient address.
    /// @param amount Number of tokens to mint.
    function mint(address to, uint256 amount) external onlyRole(MINT_ROLE) {
        _consumeMintLimit({minter: msg.sender, amount: amount});
        _mint(to, amount);
        emit Minted({minter: msg.sender, to: to, amount: amount});
    }

    /// @notice Mints `amount` tokens to `to` with a memo.
    ///
    /// @param to     Recipient address.
    /// @param amount Number of tokens to mint.
    /// @param memo   The memo associated with the mint.
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external onlyRole(MINT_ROLE) {
        _consumeLimit({key: MINT_RATE_LIMIT_KEY, account: msg.sender, amount: amount});
        _mint(to, amount);
        emit Minted({minter: msg.sender, to: to, amount: amount});
        emit Memo({memo: memo});
    }

    /// @notice Burns `amount` tokens from the caller's balance.
    ///
    /// @param amount Number of tokens to burn.
    function burn(uint256 amount) external onlyRole(BURN_ROLE) {
        _burn(msg.sender, amount);
        emit Burned({burner: msg.sender, amount: amount});
    }

    /// @notice Burns `amount` tokens from the caller's balance with a memo.
    ///
    /// @param amount Number of tokens to burn.
    /// @param memo   The memo associated with the burn.
    function burnWithMemo(uint256 amount, bytes32 memo) external onlyRole(BURN_ROLE) {
        _burn(msg.sender, amount);
        emit Burned({burner: msg.sender, amount: amount});
        emit Memo({memo: memo});
    }

    /// @notice Updates an existing minter's rate-limit configuration.
    ///
    /// @dev Cannot add or remove minters; use role management for that.
    ///
    /// @param minter   Minter address to update.
    /// @param limit    New maximum mint capacity.
    /// @param interval Replenishment interval in seconds.
    function configureMinter(address minter, uint256 limit, uint40 interval) external onlyRole(MINT_RATE_LIMIT_ROLE) {
        _checkRole({role: MINT_ROLE, account: minter});
        _configureMinter({minter: minter, limit: limit, interval: interval});
    }

    /// @notice Atomically grants `MINT_ROLE` to `minter` and configures its rate-limit in one transaction.
    ///
    /// @dev Combines {grantRole} and {configureMinter} to eliminate the two-step setup
    /// where a newly-granted minter has `MINT_ROLE` but no rate-limit config and would
    /// revert with {MinterNotConfigured} if it attempted to mint.
    ///
    /// @param minter   Address to grant `MINT_ROLE` and configure.
    /// @param limit    Maximum mint capacity.
    /// @param interval Replenishment interval in seconds.
    function grantMinterRoleWithLimit(address minter, uint256 limit, uint40 interval)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole({role: MINT_ROLE, account: minter});
        _configureMinter({minter: minter, limit: limit, interval: interval});
    }

    /// @notice Updates the blocklist status for `account`.
    ///
    /// @param account     Address to update.
    /// @param blocklisted Whether the account should be blocklisted.
    function updateBlocklistStatus(address account, bool blocklisted) external onlyRole(BLOCKLIST_ROLE) {
        _updateBlocklistStatus({account: account, blocklisted: blocklisted});
    }

    /// @notice Updates the contract-level metadata URI (ERC-7572).
    ///
    /// @param newContractURI The new metadata URI.
    function updateContractURI(string calldata newContractURI) external onlyRole(METADATA_ROLE) {
        _updateContractURI(newContractURI);
    }

    /// @notice Pauses all token transfers.
    function pause() external onlyRole(PAUSE_ROLE) {
        _pause();
    }

    /// @notice Unpauses token transfers.
    function unpause() external onlyRole(PAUSE_ROLE) {
        _unpause();
    }

    /// @notice Upgrades the beacon for this stablecoin to a new beacon address.
    ///
    /// @dev Calls `ERC1967Utils.upgradeBeaconToAndCall`, which updates the ERC-1967 beacon slot
    /// to point at `newBeacon` and optionally forwards `data` via delegatecall to the new
    /// implementation.
    ///
    /// @param newBeacon The new beacon contract address. Must implement `IBeacon`.
    /// @param data      Optional calldata to forward to the new implementation via delegatecall.
    function upgradeBeaconToAndCall(address newBeacon, bytes calldata data) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ERC1967Utils.upgradeBeaconToAndCall(newBeacon, data);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the number of decimals used for token amounts.
    ///
    /// @return The number of decimals.
    function decimals() public view override(ERC20Upgradeable, TokenMetadata) returns (uint8) {
        return TokenMetadata.decimals();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Overrides role revoking to remove the mint rate limit when `MINT_ROLE` is revoked.
    ///
    /// @param role    The role being revoked.
    /// @param account The account losing the role.
    ///
    /// @return True if the role was previously held and has now been revoked.
    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        bool revoked = super._revokeRole(role, account);
        if (revoked && role == MINT_ROLE) {
            _removeMinter({minter: account});
        }
        return revoked;
    }

    /// @notice Overrides the ERC-20 transfer hook to enforce blocklist and pause checks.
    ///
    /// @param from  The sender address.
    /// @param to    The recipient address.
    /// @param value The token amount being transferred.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        _requireNotBlocklisted({account: from});
        _requireNotBlocklisted({account: to});
        super._update(from, to, value);
    }
}
