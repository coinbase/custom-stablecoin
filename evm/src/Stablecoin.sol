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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {Blocklist} from "./lib/Blocklist.sol";
import {ERC3009Upgradeable} from "./lib/ERC3009Upgradeable.sol";
import {RateLimit} from "./lib/RateLimit.sol";
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
///     Rate limits are scoped to {MINT_RATE_LIMIT_KEY} within the {RateLimit} mixin.
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
    RateLimit,
    TokenMetadata
{
    /// @notice Role required to mint tokens up to the configured rate limit.
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");

    /// @notice Role required to burn the caller's own tokens.
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");

    /// @notice Role required to update mint rate-limit configurations for existing minters.
    bytes32 public constant MINT_RATE_LIMIT_ROLE = keccak256("MINT_RATE_LIMIT_ROLE");

    /// @notice Role required to blocklist addresses.
    bytes32 public constant BLOCKLIST_ROLE = keccak256("BLOCKLIST_ROLE");

    /// @notice Role required to unblocklist addresses.
    bytes32 public constant UNBLOCKLIST_ROLE = keccak256("UNBLOCKLIST_ROLE");

    /// @notice Role required to update the contract-level metadata URI (ERC-7572).
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");

    /// @notice Role required to pause all token transfers.
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    /// @notice Role required to unpause all token transfers.
    bytes32 public constant UNPAUSE_ROLE = keccak256("UNPAUSE_ROLE");

    /// @notice Rate-limit key scoping mint capacity. Passed to {RateLimit} for all mint-related operations.
    bytes32 public constant MINT_RATE_LIMIT_KEY = keccak256("MINT_RATE_LIMIT");

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
    /// @dev The {Memo} event is emitted immediately after the ERC-20 {Transfer} event.
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
    /// @dev The {Memo} event is emitted immediately after the ERC-20 {Transfer} event.
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
        _consumeLimit({key: MINT_RATE_LIMIT_KEY, account: msg.sender, amount: amount});
        _mint(to, amount);
        emit Minted({minter: msg.sender, to: to, amount: amount});
    }

    /// @notice Mints `amount` tokens to `to` with a memo.
    ///
    /// @dev The {Memo} event is emitted immediately after the ERC-20 {Transfer} event.
    ///
    /// @param to     Recipient address.
    /// @param amount Number of tokens to mint.
    /// @param memo   The memo associated with the mint.
    function mintWithMemo(address to, uint256 amount, bytes32 memo) external onlyRole(MINT_ROLE) {
        _consumeLimit({key: MINT_RATE_LIMIT_KEY, account: msg.sender, amount: amount});
        _mint(to, amount);
        emit Memo({memo: memo});
        emit Minted({minter: msg.sender, to: to, amount: amount});
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
    /// @dev The {Memo} event is emitted immediately after the ERC-20 {Transfer} event.
    ///
    /// @param amount Number of tokens to burn.
    /// @param memo   The memo associated with the burn.
    function burnWithMemo(uint256 amount, bytes32 memo) external onlyRole(BURN_ROLE) {
        _burn(msg.sender, amount);
        emit Memo({memo: memo});
        emit Burned({burner: msg.sender, amount: amount});
    }

    /// @notice Updates an existing minter's rate-limit configuration.
    ///
    /// @dev Cannot add or remove minters; use role management for that.
    /// Configuring a new limit resets the remaining capacity to the full limit.
    ///
    /// @param minter   Minter address to update.
    /// @param limit    New maximum mint capacity.
    /// @param interval Replenishment interval in seconds.
    function configureMinter(address minter, uint216 limit, uint40 interval) external onlyRole(MINT_RATE_LIMIT_ROLE) {
        _checkRole({role: MINT_ROLE, account: minter});
        _configureRateLimit({key: MINT_RATE_LIMIT_KEY, account: minter, limit: limit, interval: interval});
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
    function grantMinterRoleWithLimit(address minter, uint216 limit, uint40 interval)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole({role: MINT_ROLE, account: minter});
        _configureRateLimit({key: MINT_RATE_LIMIT_KEY, account: minter, limit: limit, interval: interval});
    }

    /// @notice Blocks `account` from the blocklist.
    ///
    /// @param account Address to block.
    function blocklist(address account) external onlyRole(BLOCKLIST_ROLE) {
        _updateBlocklistStatus({account: account, blocklisted: true});
    }

    /// @notice Unblocks `account` from the blocklist.
    ///
    /// @param account Address to unblock.
    function unblocklist(address account) external onlyRole(UNBLOCKLIST_ROLE) {
        _updateBlocklistStatus({account: account, blocklisted: false});
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
    function unpause() external onlyRole(UNPAUSE_ROLE) {
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

    /// @notice Declares ERC-165 support for ERC-20, ERC-2612 (Permit), and inherited interfaces.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IERC20Permit).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /// @notice Returns the current mint capacity for `minter`.
    ///
    /// @param minter The minter address to query.
    ///
    /// @return The current available mint capacity.
    function currentMintLimit(address minter) public view returns (uint256) {
        return currentLimit({key: MINT_RATE_LIMIT_KEY, account: minter});
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
            _removeRateLimit({key: MINT_RATE_LIMIT_KEY, account: account});
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
        _requireNotBlocklisted({account: msg.sender});
        _requireNotBlocklisted({account: from});
        _requireNotBlocklisted({account: to});
        ERC20PausableUpgradeable._update(from, to, value);
    }

    /// @notice Returns msg.sender directly rather than letting ContextUpgradeable handle it.
    /// @dev This function should remain unmodified as we will not be implementing erc-2771 meta-transactions.
    function _msgSender() internal view override returns (address) {
        return msg.sender;
    }

    /// @notice Overrides the ERC-20 approve hook to enforce blocklist checks.
    ///
    /// @param owner     The owner address.
    /// @param spender   The spender address.
    /// @param value     The token amount being approved.
    /// @param emitEvent Whether to emit the {Approval} event.
    function _approve(address owner, address spender, uint256 value, bool emitEvent)
        internal
        override(ERC20Upgradeable)
    {
        _requireNotBlocklisted({account: msg.sender});
        _requireNotBlocklisted({account: owner});
        _requireNotBlocklisted({account: spender});
        ERC20Upgradeable._approve(owner, spender, value, emitEvent);
    }
}
