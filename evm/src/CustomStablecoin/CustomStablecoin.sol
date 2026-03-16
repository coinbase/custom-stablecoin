// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {BlacklistStorage} from "./lib/BlacklistStorage.sol";
import {MetadataStorage} from "./lib/MetadataStorage.sol";
import {MintAllowanceStorage} from "./lib/MintAllowanceStorage.sol";

/// @title CustomStablecoin
/// @author Coinbase
/// @notice Custom stablecoin implementation, upgradeable via a beacon proxy.
///
/// @dev Roles:
///   - DEFAULT_ADMIN_ROLE – can grant/revoke all other roles. Two-step
///     transfer with configurable delay.
///   - MINT_ROLE – can mint tokens up to their configured allowance.
///     Granting MINT_ROLE auto-configures a default allowance (1,000,000 tokens / 24h).
///     Revoking MINT_ROLE clears the allowance.
///   - MINT_ALLOWANCE_ROLE – can update allowances for existing minters.
///   - BURN_ROLE – can burn their own tokens.
///   - PAUSE_ROLE – can pause/unpause all transfers.
///   - BLACKLIST_ROLE – can blacklist/unblacklist addresses.
contract CustomStablecoin is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable
{
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant MINT_ALLOWANCE_ROLE = keccak256("MINT_ALLOWANCE_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant BLACKLIST_ROLE = keccak256("BLACKLIST_ROLE");

    uint256 public constant DEFAULT_MINT_ALLOWANCE = 1_000_000;
    uint256 public constant DEFAULT_MINT_INTERVAL = 24 hours;

    /// @notice Default role assignments passed to {initialize}.
    struct Roles {
        address minter;
        address mintAllowance;
        address burner;
        address pauser;
        address blacklister;
    }

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

    /// @notice Thrown when a minter address has no configured allowance.
    ///
    /// @param minter The unconfigured minter address.
    error MinterNotConfigured(address minter);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the stablecoin with the given admin, delay, name, symbol, decimals, and role assignments.
    ///
    /// @param admin         The initial default admin address.
    /// @param adminDelay    Delay (in seconds) for admin transfer proposals.
    /// @param name          Token name.
    /// @param symbol        Token symbol.
    /// @param tokenDecimals Token decimal places (max 18).
    /// @param roles         Default role assignments for each operational role.
    function initialize(
        address admin,
        uint48 adminDelay,
        string memory name,
        string memory symbol,
        uint8 tokenDecimals,
        Roles memory roles
    ) external initializer {
        MetadataStorage.setDecimals({value: tokenDecimals});
        __ERC20_init(name, symbol);
        __ERC20Pausable_init();
        __AccessControlDefaultAdminRules_init(adminDelay, admin);
        _grantRole({role: MINT_ALLOWANCE_ROLE, account: roles.mintAllowance});
        _grantRole({role: MINT_ROLE, account: roles.minter});
        _grantRole({role: BURN_ROLE, account: roles.burner});
        _grantRole({role: PAUSE_ROLE, account: roles.pauser});
        _grantRole({role: BLACKLIST_ROLE, account: roles.blacklister});
    }

    /// @notice Mints `amount` tokens to `to`.
    ///
    /// @param to     Recipient address.
    /// @param amount Number of tokens to mint.
    function mint(address to, uint256 amount) external onlyRole(MINT_ROLE) {
        MintAllowanceStorage.consume({minter: msg.sender, amount: amount});
        _mint(to, amount);
        emit Minted({minter: msg.sender, to: to, amount: amount});
    }

    /// @notice Updates an existing minter's rate-limit configuration.
    ///
    /// @dev Cannot add or remove minters; use role management for that.
    ///
    /// @param minter       Minter address to update.
    /// @param maxAllowance New maximum allowance per interval.
    /// @param interval     Replenishment interval in seconds.
    function updateMinterAllowance(address minter, uint256 maxAllowance, uint256 interval)
        external
        onlyRole(MINT_ALLOWANCE_ROLE)
    {
        if (!hasRole(MINT_ROLE, minter)) revert MinterNotConfigured({minter: minter});
        MintAllowanceStorage.configureMinter(minter, maxAllowance, interval);
    }

    /// @notice Burns `amount` tokens from the caller's balance.
    ///
    /// @param amount Number of tokens to burn.
    function burn(uint256 amount) external onlyRole(BURN_ROLE) {
        _burn(msg.sender, amount);
        emit Burned({burner: msg.sender, amount: amount});
    }

    /// @notice Pauses all token transfers.
    function pause() external onlyRole(PAUSE_ROLE) {
        _pause();
    }

    /// @notice Unpauses token transfers.
    function unpause() external onlyRole(PAUSE_ROLE) {
        _unpause();
    }

    /// @notice Adds `account` to the blacklist, preventing it from transferring tokens.
    ///
    /// @param account Address to blacklist.
    function blacklist(address account) external onlyRole(BLACKLIST_ROLE) {
        BlacklistStorage.blacklist(account);
    }

    /// @notice Removes `account` from the blacklist.
    ///
    /// @param account Address to unblacklist.
    function unBlacklist(address account) external onlyRole(BLACKLIST_ROLE) {
        BlacklistStorage.unBlacklist(account);
    }

    /// @notice Returns the estimated current mint allowance for `caller`.
    ///
    /// @dev Includes any pending replenishment that would apply at the current timestamp.
    ///
    /// @param caller Address to query.
    ///
    /// @return Current allowance including any pending replenishment.
    function estimatedAllowance(address caller) external view returns (uint256) {
        return MintAllowanceStorage.estimatedAllowance({minter: caller});
    }

    /// @notice Returns whether `account` is blacklisted.
    ///
    /// @param account Address to query.
    ///
    /// @return True if the address is blacklisted.
    function isBlacklisted(address account) external view returns (bool) {
        return BlacklistStorage.isBlacklisted(account);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the number of decimals used for token amounts.
    function decimals() public view override returns (uint8) {
        return MetadataStorage.getDecimals();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Overrides role granting to auto-configure a mint allowance when `MINT_ROLE` is granted.
    ///
    /// @param role    The role being granted.
    /// @param account The account receiving the role.
    ///
    /// @return True if the role was newly granted.
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        bool granted = super._grantRole(role, account);
        if (granted && role == MINT_ROLE) {
            uint256 allowance = DEFAULT_MINT_ALLOWANCE * 10 ** decimals();
            MintAllowanceStorage.configureMinter({
                minter: account, maxAllowance: allowance, interval: DEFAULT_MINT_INTERVAL
            });
        }
        return granted;
    }

    /// @notice Overrides role revoking to remove the mint allowance when `MINT_ROLE` is revoked.
    ///
    /// @param role    The role being revoked.
    /// @param account The account losing the role.
    ///
    /// @return True if the role was previously held and has now been revoked.
    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        bool revoked = super._revokeRole(role, account);
        if (revoked && role == MINT_ROLE) {
            MintAllowanceStorage.removeMinter({minter: account});
        }
        return revoked;
    }

    /// @notice Overrides the ERC-20 transfer hook to enforce blacklist and pause checks.
    ///
    /// @param from  The sender address.
    /// @param to    The recipient address.
    /// @param value The token amount being transferred.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        BlacklistStorage.requireNotBlacklisted({account: msg.sender});
        BlacklistStorage.requireNotBlacklisted({account: from});
        BlacklistStorage.requireNotBlacklisted({account: to});
        super._update(from, to, value);
    }
}
