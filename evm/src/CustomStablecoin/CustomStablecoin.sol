// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {MetadataStorage} from "./lib/MetadataStorage.sol";
import {BlacklistStorage} from "./lib/BlacklistStorage.sol";
import {MintAllowanceStorage} from "./lib/MintAllowanceStorage.sol";

/**
 * @dev Custom stablecoin implementation, upgradeable via a beacon proxy.
 *
 * Roles:
 *   - DEFAULT_ADMIN_ROLE – can grant/revoke all other roles. Two-step
 *     transfer with configurable delay.
 *   - MINT_ROLE – can mint tokens up to their configured allowance.
 *     Granting MINT_ROLE auto-configures a default allowance ($1,000,000 / 24h).
 *     Revoking MINT_ROLE clears the allowance.
 *   - MINT_ALLOWANCE_ROLE – can update allowances for existing minters.
 *   - PAUSE_ROLE – can pause/unpause all transfers.
 *   - BLACKLIST_ROLE – can blacklist/unblacklist addresses.
 */
contract CustomStablecoin is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlDefaultAdminRulesUpgradeable
{
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant MINT_ALLOWANCE_ROLE = keccak256("MINT_ALLOWANCE_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant BLACKLIST_ROLE = keccak256("BLACKLIST_ROLE");

    uint256 public constant DEFAULT_MINT_ALLOWANCE = 1_000_000;
    uint256 public constant DEFAULT_MINT_INTERVAL = 24 hours;

    error MinterNotConfigured(address minter);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        uint48 adminDelay,
        string memory name,
        string memory symbol,
        uint8 tokenDecimals
    ) external initializer {
        MetadataStorage.setDecimals(tokenDecimals);
        __ERC20_init(name, symbol);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControlDefaultAdminRules_init(adminDelay, admin);
        _grantRole(MINT_ALLOWANCE_ROLE, admin);
        _grantRole(MINT_ROLE, admin);
        _grantRole(PAUSE_ROLE, admin);
        _grantRole(BLACKLIST_ROLE, admin);
    }

    function decimals() public view override returns (uint8) {
        return MetadataStorage.getDecimals();
    }

    // -------------------------------------------------------------------------
    // Minting (rate-limited)
    // -------------------------------------------------------------------------

    function mint(address to, uint256 amount) external onlyRole(MINT_ROLE) {
        MintAllowanceStorage.consume(msg.sender, amount);
        _mint(to, amount);
    }

    /**
     * @dev Updates an existing minter's allowance. Cannot add or remove minters.
     */
    function updateMinterAllowance(address minter, uint256 maxAllowance, uint256 interval)
        external
        onlyRole(MINT_ALLOWANCE_ROLE)
    {
        if (!hasRole(MINT_ROLE, minter)) revert MinterNotConfigured(minter);
        MintAllowanceStorage.configureMinter(minter, maxAllowance, interval);
    }

    function estimatedAllowance(address caller) external view returns (uint256) {
        return MintAllowanceStorage.estimatedAllowance(caller);
    }

    // -------------------------------------------------------------------------
    // Pause
    // -------------------------------------------------------------------------

    function pause() external onlyRole(PAUSE_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSE_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------------------
    // Blacklist
    // -------------------------------------------------------------------------

    function blacklist(address account) external onlyRole(BLACKLIST_ROLE) {
        BlacklistStorage.blacklist(account);
    }

    function unBlacklist(address account) external onlyRole(BLACKLIST_ROLE) {
        BlacklistStorage.unBlacklist(account);
    }

    function isBlacklisted(address account) external view returns (bool) {
        return BlacklistStorage.isBlacklisted(account);
    }

    // -------------------------------------------------------------------------
    // Internal — role grant/revoke hooks
    // -------------------------------------------------------------------------

    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        bool granted = super._grantRole(role, account);
        if (granted && role == MINT_ROLE) {
            uint256 allowance = DEFAULT_MINT_ALLOWANCE * 10 ** decimals();
            MintAllowanceStorage.configureMinter(account, allowance, DEFAULT_MINT_INTERVAL);
        }
        return granted;
    }

    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        bool revoked = super._revokeRole(role, account);
        if (revoked && role == MINT_ROLE) {
            MintAllowanceStorage.removeMinter(account);
        }
        return revoked;
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        BlacklistStorage.requireNotBlacklisted(from);
        BlacklistStorage.requireNotBlacklisted(to);
        super._update(from, to, value);
    }
}
