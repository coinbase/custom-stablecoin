// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {MutableBeaconProxy} from "./MutableBeaconProxy.sol";
import {Stablecoin} from "./Stablecoin.sol";

/// @title StablecoinFactory
/// @author Coinbase
/// @notice UUPS-upgradeable factory that deploys {MutableBeaconProxy} proxies pointing to a shared {Stablecoin} implementation.
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
contract StablecoinFactory is Initializable, AccessControlDefaultAdminRulesUpgradeable, UUPSUpgradeable {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for factory state.
    /// @custom:storage-location erc7201:coinbase.storage.StablecoinFactory
    struct FactoryStorage {
        /// @dev The shared beacon address used by all deployed proxies.
        address beacon;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.StablecoinFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FACTORY_STORAGE_LOCATION =
        0x0359e5965fc60a4d7c47813a3cae31d4fea873da7c55a52a52894a5078215f00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new stablecoin is deployed.
    /// @param stablecoin  The address of the new stablecoin.
    event StablecoinDeployed(address indexed stablecoin);

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

    /// @notice Initializes the factory with an admin, delay, beacon, and deployer.
    ///
    /// @param admin      Initial default admin (two-step transfer with delay).
    /// @param adminDelay Delay (in seconds) for admin transfer proposals.
    /// @param beacon_    Beacon address; set once and cannot be changed.
    /// @param deployer   Address that can deploy new {Stablecoin} instances.
    function initialize(address admin, uint48 adminDelay, address beacon_, address deployer) external initializer {
        if (beacon_ == address(0)) revert BeaconNotSet();
        __AccessControlDefaultAdminRules_init({initialDelay: adminDelay, initialDefaultAdmin: admin});
        _getFactoryStorage().beacon = beacon_;
        _grantRole({role: DEPLOYER_ROLE, account: deployer});
    }

    /// @notice Deploys a new {Stablecoin} behind an {MutableBeaconProxy} using CREATE2.
    ///
    /// @dev Uses `Create2.deploy` so the factory's address is part of the CREATE2 derivation,
    /// ensuring only this factory can deploy proxies to the predicted addresses.
    ///
    /// @param name          Token name.
    /// @param symbol        Token symbol.
    /// @param decimals Token decimal places (max 18).
    /// @param stablecoinAdmin The initial default admin of the Stablecoin.
    /// @param salt          Salt for CREATE2; determines the proxy address.
    ///
    /// @return stablecoin The address of the newly deployed stablecoin.
    function deploy(string calldata name, string calldata symbol, uint8 decimals, address stablecoinAdmin, bytes32 salt)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address stablecoin)
    {
        stablecoin =
            Create2.deploy({amount: 0, salt: salt, bytecode: _bytecode(name, symbol, decimals, stablecoinAdmin)});
        emit StablecoinDeployed(stablecoin);
    }

    /// @notice Returns the deterministic address for a proxy deployed with the given
    /// parameters, whether or not it has been deployed.
    ///
    /// @param name          Token name.
    /// @param symbol        Token symbol.
    /// @param decimals Token decimal places (max 18).
    /// @param stablecoinAdmin The initial default admin of the Stablecoin.
    /// @param salt          The CREATE2 salt.
    ///
    /// @return The deterministic stablecoin address.
    function computeAddress(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address stablecoinAdmin,
        bytes32 salt
    ) external view returns (address) {
        return Create2.computeAddress(salt, keccak256(_bytecode(name, symbol, decimals, stablecoinAdmin)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the shared beacon address used by all proxies deployed from this factory.
    ///
    /// @return The beacon address.
    function beacon() public view returns (address) {
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

    /// @notice Builds the full creation bytecode for an {MutableBeaconProxy} that
    /// initializes a {Stablecoin} with the given parameters.
    function _bytecode(string calldata name, string calldata symbol, uint8 decimals, address stablecoinAdmin)
        private
        view
        returns (bytes memory)
    {
        bytes memory data = abi.encodeCall(Stablecoin.initialize, (name, symbol, decimals, stablecoinAdmin));
        return abi.encodePacked(type(MutableBeaconProxy).creationCode, abi.encode(beacon(), data));
    }

    /// @notice Returns a storage pointer to the ERC-7201 namespaced factory layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getFactoryStorage() private pure returns (FactoryStorage storage $) {
        assembly {
            $.slot := FACTORY_STORAGE_LOCATION
        }
    }
}
