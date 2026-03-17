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
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

import {Sanctionable} from "./lib/Sanctionable.sol";
import {ERC3009Upgradeable} from "./lib/ERC3009Upgradeable.sol";
import {MintRateLimit} from "./lib/MintRateLimit.sol";
import {TokenMetadata} from "./lib/TokenMetadata.sol";

/// @title Stablecoin
/// @author Coinbase
/// @notice Stablecoin implementation, upgradeable via a beacon proxy.
///
/// @dev Roles:
///   - DEFAULT_ADMIN_ROLE – can grant/revoke all other roles. Two-step
///     transfer with configurable delay.
///   - MINT_ROLE – can mint tokens up to their configured rate limit.
///     After granting, a MINT_RATE_LIMIT_ROLE holder must call {configureMinter}
///     to set the rate limit. Revoking MINT_ROLE clears the rate limit.
///   - MINT_RATE_LIMIT_ROLE – can update rate limits for existing minters.
///   - BURN_ROLE – can burn their own tokens.
///   - PAUSE_ROLE – can pause/unpause all transfers.
///   - SANCTION_ROLE – can update sanction status for addresses.
///   - METADATA_ROLE – can update the contract-level metadata URI (ERC-7572).
contract Stablecoin is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    ERC20PermitUpgradeable,
    ERC3009Upgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    Sanctionable,
    MintRateLimit,
    TokenMetadata
{
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant MINT_RATE_LIMIT_ROLE = keccak256("MINT_RATE_LIMIT_ROLE");
    bytes32 public constant SANCTION_ROLE = keccak256("SANCTION_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");

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

    /// @notice Thrown when the provided implementation address has no code or is the zero address.
    ///
    /// @param implementation The invalid implementation address.
    error InvalidImplementation(address implementation);

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

    /// @notice Mints `amount` tokens to `to`.
    ///
    /// @param to     Recipient address.
    /// @param amount Number of tokens to mint.
    function mint(address to, uint256 amount) external onlyRole(MINT_ROLE) {
        _consumeMintLimit({minter: msg.sender, amount: amount});
        _mint(to, amount);
        emit Minted({minter: msg.sender, to: to, amount: amount});
    }

    /// @notice Burns `amount` tokens from the caller's balance.
    ///
    /// @param amount Number of tokens to burn.
    function burn(uint256 amount) external onlyRole(BURN_ROLE) {
        _burn(msg.sender, amount);
        emit Burned({burner: msg.sender, amount: amount});
    }

    /// @notice Updates an existing minter's rate-limit configuration.
    ///
    /// @dev Cannot add or remove minters; use role management for that.
    ///
    /// @param minter   Minter address to update.
    /// @param limit    New maximum mint capacity.
    /// @param interval Replenishment interval in seconds.
    function configureMinter(address minter, uint256 limit, uint256 interval) external onlyRole(MINT_RATE_LIMIT_ROLE) {
        _checkRole(MINT_ROLE, minter);
        _configureMinter(minter, limit, interval);
    }

    /// @notice Updates the sanction status for `account`.
    ///
    /// @param account    Address to update.
    /// @param sanctioned Whether the account should be sanctioned.
    function updateSanctionStatus(address account, bool sanctioned) external onlyRole(SANCTION_ROLE) {
        _updateSanctionStatus(account, sanctioned);
    }

    /// @notice Pauses all token transfers.
    function pause() external onlyRole(PAUSE_ROLE) {
        _pause();
    }

    /// @notice Unpauses token transfers.
    function unpause() external onlyRole(PAUSE_ROLE) {
        _unpause();
    }

    /// @notice Updates the contract-level metadata URI (ERC-7572).
    ///
    /// @param newContractURI The new metadata URI.
    function updateContractURI(string calldata newContractURI) external onlyRole(METADATA_ROLE) {
        _updateContractURI(newContractURI);
    }

    /// @notice Permanently opts this proxy out of the shared beacon by writing a direct
    /// implementation address into the ERC-1967 implementation slot.
    ///
    /// @dev After this call, the proxy's `_implementation()` returns `newImplementation`
    /// directly instead of querying the beacon. This is a one-way operation — once set,
    /// the proxy no longer follows beacon upgrades. The admin can still call this again
    /// to point at a different implementation, but cannot return to beacon behavior.
    ///
    /// @param newImplementation The implementation address to delegate to. Must be a deployed
    ///        contract (non-zero address with code).
    function exitBeacon(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Ensure the target is a deployed contract, not an EOA or empty address.
        if (newImplementation.code.length == 0) revert InvalidImplementation({implementation: newImplementation});

        // Write directly to the ERC-1967 implementation slot. Once set, the proxy's
        // _implementation() will return this address, bypassing the beacon entirely.
        StorageSlot.getAddressSlot(ERC1967Utils.IMPLEMENTATION_SLOT).value = newImplementation;

        emit IERC1967.Upgraded(newImplementation);
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

    /// @notice Overrides the ERC-20 transfer hook to enforce sanction and pause checks.
    ///
    /// @param from  The sender address.
    /// @param to    The recipient address.
    /// @param value The token amount being transferred.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        _requireNotSanctioned({account: msg.sender});
        _requireNotSanctioned({account: from});
        _requireNotSanctioned({account: to});
        super._update(from, to, value);
    }
}
