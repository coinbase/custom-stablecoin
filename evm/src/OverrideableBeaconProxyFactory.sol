// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {OverrideableBeaconProxy} from "./OverrideableBeaconProxy.sol";

/// @title OverrideableBeaconProxyFactory
/// @author Coinbase
/// @notice UUPS-upgradeable factory that deploys {OverrideableBeaconProxy} instances
/// pointing to a shared beacon.
///
/// @dev The beacon is set once during initialization and cannot be changed.
///
/// Roles:
///   - DEFAULT_ADMIN_ROLE – can upgrade the factory and manage roles
///     (grant/revoke DEPLOYER_ROLE). Transfer is two-step with a configurable delay.
///   - DEPLOYER_ROLE – can deploy new proxy instances via {deploy}.
///
/// All mutable state lives in an ERC-7201 namespaced storage struct so the
/// layout is upgrade-safe and collision-resistant.
contract OverrideableBeaconProxyFactory is Initializable, AccessControlDefaultAdminRulesUpgradeable, UUPSUpgradeable {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for factory state.
    /// @custom:storage-location erc7201:coinbase.storage.OverrideableBeaconProxyFactory
    struct FactoryStorage {
        /// @dev The shared beacon address used by all deployed proxies.
        address beacon;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.OverrideableBeaconProxyFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FACTORY_STORAGE_LOCATION =
        0x2f479ea380745b703f8a394ca62a27f1007b7f21f9ec66b12e43f39167f1b900;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new proxy is deployed.
    ///
    /// @param proxy  The address of the deployed proxy.
    /// @param admin  The proxy admin address.
    /// @param salt   The CREATE2 salt used for deployment.
    event ProxyDeployed(address indexed proxy, address indexed admin, bytes32 salt);

    /// @notice Thrown when the factory is initialized without a beacon address.
    error BeaconNotSet();

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

    /// @notice Initializes the factory with an admin, delay, and beacon address.
    ///
    /// @param admin      Initial default admin (two-step transfer with delay).
    /// @param adminDelay Delay (in seconds) for admin transfer proposals.
    /// @param beacon_    Beacon address; set once and cannot be changed.
    function initialize(address admin, uint48 adminDelay, address beacon_) external initializer {
        if (beacon_ == address(0)) revert BeaconNotSet();
        __AccessControlDefaultAdminRules_init(adminDelay, admin);
        _grantRole({role: DEPLOYER_ROLE, account: admin});
        _getFactoryStorage().beacon = beacon_;
    }

    /// @notice Deploys a new {OverrideableBeaconProxy} using CREATE2 for deterministic addresses.
    ///
    /// @param salt   Salt for CREATE2; determines the proxy address.
    /// @param admin  The admin of the new proxy (controls implementation override).
    /// @param data   Optional initializer calldata forwarded via delegatecall.
    ///
    /// @return The address of the newly deployed proxy.
    function deploy(bytes32 salt, address admin, bytes calldata data)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address)
    {
        address proxy = address(new OverrideableBeaconProxy{salt: salt}(_getFactoryStorage().beacon, admin, data));
        emit ProxyDeployed({proxy: proxy, admin: admin, salt: salt});
        return proxy;
    }

    /// @notice Returns the deterministic address for a proxy deployed with the given
    /// salt and constructor arguments, whether or not it has been deployed.
    ///
    /// @param salt   The CREATE2 salt.
    /// @param admin  The proxy admin address.
    /// @param data   The initializer calldata.
    ///
    /// @return The deterministic proxy address.
    function getAddress(bytes32 salt, address admin, bytes calldata data) external view returns (address) {
        bytes memory creationCode = abi.encodePacked(
            type(OverrideableBeaconProxy).creationCode, abi.encode(_getFactoryStorage().beacon, admin, data)
        );
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(creationCode)));
        return address(uint160(uint256(hash)));
    }

    /// @notice Returns the shared beacon address used by all proxies deployed from this factory.
    ///
    /// @return The beacon address.
    function beacon() external view returns (address) {
        return _getFactoryStorage().beacon;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Restricts UUPS upgrades to the default admin.
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns a storage pointer to the ERC-7201 namespaced factory layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getFactoryStorage() private pure returns (FactoryStorage storage $) {
        // Assembly is required to load from the ERC-7201 namespaced storage slot.
        assembly {
            $.slot := FACTORY_STORAGE_LOCATION
        }
    }
}
