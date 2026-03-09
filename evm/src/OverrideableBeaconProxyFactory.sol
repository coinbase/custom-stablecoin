// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OverrideableBeaconProxy} from "./OverrideableBeaconProxy.sol";

/**
 * @dev UUPS-upgradeable factory that deploys {OverrideableBeaconProxy} instances
 * pointing to a shared beacon.
 *
 * The beacon is set once during initialization and cannot be changed.
 *
 * Roles:
 *   - DEFAULT_ADMIN_ROLE – can upgrade the factory and manage roles
 *     (grant/revoke DEPLOYER_ROLE). Transfer is two-step with a configurable delay.
 *   - DEPLOYER_ROLE – can deploy new proxy instances via {deploy}.
 *
 * All mutable state lives in an ERC-7201 namespaced storage struct so the
 * layout is upgrade-safe and collision-resistant.
 */
contract OverrideableBeaconProxyFactory is
    Initializable,
    AccessControlDefaultAdminRulesUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    // -------------------------------------------------------------------------
    // ERC-7201 namespaced storage
    // -------------------------------------------------------------------------

    /// @custom:storage-location erc7201:coinbase.storage.OverrideableBeaconProxyFactory
    struct FactoryStorage {
        address beacon;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.OverrideableBeaconProxyFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FACTORY_STORAGE_LOCATION =
        0x2f479ea380745b703f8a394ca62a27f1007b7f21f9ec66b12e43f39167f1b900;

    function _getFactoryStorage() private pure returns (FactoryStorage storage $) {
        assembly {
            $.slot := FACTORY_STORAGE_LOCATION
        }
    }

    // -------------------------------------------------------------------------
    // Events / errors
    // -------------------------------------------------------------------------

    event ProxyDeployed(address indexed proxy, address indexed owner, bytes32 salt);

    error BeaconNotSet();

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @param admin        Initial default admin (two-step transfer with delay).
     * @param adminDelay   Delay (in seconds) for admin transfer proposals.
     * @param beacon_      Beacon address; set once and cannot be changed.
     */
    function initialize(address admin, uint48 adminDelay, address beacon_) external initializer {
        if (beacon_ == address(0)) revert BeaconNotSet();
        __AccessControlDefaultAdminRules_init(adminDelay, admin);
        _grantRole(DEPLOYER_ROLE, admin);
        _getFactoryStorage().beacon = beacon_;
    }

    // -------------------------------------------------------------------------
    // Deployer functions
    // -------------------------------------------------------------------------

    /**
     * @dev Deploys a new {OverrideableBeaconProxy} using CREATE2 for deterministic addresses.
     * @param salt    Salt for CREATE2; determines the proxy address.
     * @param owner_  The owner of the new proxy (controls implementation override).
     * @param data    Optional initializer calldata forwarded via delegatecall.
     * @return proxy  The address of the newly deployed proxy.
     */
    function deploy(bytes32 salt, address owner_, bytes calldata data)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address proxy)
    {
        proxy = address(new OverrideableBeaconProxy{salt: salt}(_getFactoryStorage().beacon, owner_, data));
        emit ProxyDeployed(proxy, owner_, salt);
    }

    /**
     * @dev Returns the deterministic address for a proxy deployed with the given
     *      salt and constructor arguments, whether or not it has been deployed.
     */
    function getAddress(bytes32 salt, address owner_, bytes calldata data)
        external
        view
        returns (address)
    {
        bytes memory creationCode = abi.encodePacked(
            type(OverrideableBeaconProxy).creationCode,
            abi.encode(_getFactoryStorage().beacon, owner_, data)
        );
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(creationCode))
        );
        return address(uint160(uint256(hash)));
    }

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    function beacon() external view returns (address) {
        return _getFactoryStorage().beacon;
    }

    // -------------------------------------------------------------------------
    // UUPS
    // -------------------------------------------------------------------------

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
