// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

import {MutableBeaconProxy} from "./MutableBeaconProxy.sol";
import {Stablecoin} from "./Stablecoin.sol";

/// @title StablecoinFactory
/// @notice UUPS-upgradeable factory that deploys stablecoins via two paths: the legacy
/// {MutableBeaconProxy} beacon-proxy path ({deploy}) and Base-native B-20 issuance through the
/// canonical {IB20Factory} precompile ({deployB20}).
///
/// @dev The beacon is set at construction time as an immutable and backs the legacy {deploy} path.
/// Note that upgrading the factory implementation via UUPS will adopt the new implementation's
/// BEACON value. The B-20 path ({deployB20}) does not use the beacon: it is a thin,
/// access-controlled wrapper over the permissionless {IB20Factory.createB20} entry point.
/// @author Coinbase
///
/// Roles:
///   - DEFAULT_ADMIN_ROLE – can upgrade the factory and manage roles
///     (grant/revoke DEPLOYER_ROLE). Transfer is two-step with a configurable delay.
///   - DEPLOYER_ROLE – can deploy proxy instances via {deploy} and issue B-20 stablecoins via {deployB20}.
contract StablecoinFactory is Initializable, AccessControlDefaultAdminRulesUpgradeable, UUPSUpgradeable {
    /// @notice Role required to deploy {Stablecoin} proxy instances via {deploy} or issue B-20
    /// stablecoins via {deployB20}.
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    /// @notice The shared beacon address used by all proxies deployed via {deploy}.
    address public immutable BEACON;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new stablecoin is deployed.
    /// @param stablecoin  The address of the new stablecoin.
    event StablecoinDeployed(
        address indexed stablecoin,
        string name,
        string symbol,
        uint8 decimals,
        address indexed stablecoinAdmin,
        bytes32 indexed salt
    );

    /// @notice Thrown when the factory is constructed without a beacon address.
    error BeaconNotSet();

    /// @notice Thrown when a stablecoin deployment uses a zero admin.
    error StablecoinAdminRequired();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the immutable beacon address and disables initializers on the implementation.
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param beacon The shared beacon address for all proxies deployed by this factory.
    constructor(address beacon) {
        if (beacon == address(0)) revert BeaconNotSet();
        BEACON = beacon;
        _disableInitializers();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the factory with an admin, delay, and deployer.
    ///
    /// @param admin      Initial default admin (two-step transfer with delay).
    /// @param adminDelay Delay (in seconds) for admin transfer proposals.
    /// @param deployer   Address that can deploy new {Stablecoin} instances.
    function initialize(address admin, uint48 adminDelay, address deployer) external initializer {
        __AccessControlDefaultAdminRules_init({initialDelay: adminDelay, initialDefaultAdmin: admin});
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
        if (stablecoinAdmin == address(0)) revert StablecoinAdminRequired();

        stablecoin =
            Create2.deploy({amount: 0, salt: salt, bytecode: _bytecode(name, symbol, decimals, stablecoinAdmin)});
        emit StablecoinDeployed({
            stablecoin: stablecoin,
            name: name,
            symbol: symbol,
            decimals: decimals,
            stablecoinAdmin: stablecoinAdmin,
            salt: salt
        });
    }

    /// @notice Issues a new B-20 STABLECOIN token via the {IB20Factory} precompile.
    /// @dev Decimals are fixed at 6. Reverts with `StablecoinAdminRequired` when `stablecoinAdmin` is zero.
    ///
    /// @param name           Token name.
    /// @param symbol         Token symbol.
    /// @param currency       Immutable currency code; uppercase ASCII `A`-`Z` only.
    /// @param stablecoinAdmin The initial default admin of the stablecoin.
    /// @param salt           Salt for deterministic address derivation.
    ///
    /// @return stablecoin The address of the newly issued stablecoin.
    function deployB20(
        string calldata name,
        string calldata symbol,
        string calldata currency,
        address stablecoinAdmin,
        bytes32 salt
    ) external onlyRole(DEPLOYER_ROLE) returns (address stablecoin) {
        if (stablecoinAdmin == address(0)) revert StablecoinAdminRequired();

        bytes memory params = B20FactoryLib.encodeStablecoinCreateParams({
            name: name, symbol: symbol, initialAdmin: stablecoinAdmin, currency: currency
        });
        stablecoin = StdPrecompiles.B20_FACTORY
            .createB20({
                variant: IB20Factory.B20Variant.STABLECOIN,
                salt: _deriveB20Salt({
                    name: name, symbol: symbol, currency: currency, stablecoinAdmin: stablecoinAdmin, salt: salt
                }),
                params: params,
                initCalls: new bytes[](0)
            });
        emit StablecoinDeployed({
            stablecoin: stablecoin,
            name: name,
            symbol: symbol,
            decimals: IB20(stablecoin).decimals(),
            stablecoinAdmin: stablecoinAdmin,
            salt: salt
        });
    }

    /// @notice Returns the deterministic address for a legacy beacon-proxy stablecoin with the given
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

    /// @notice Returns the deterministic address for a B-20 stablecoin with the given parameters.
    ///
    /// @param name           Token name.
    /// @param symbol         Token symbol.
    /// @param currency       Immutable currency code.
    /// @param stablecoinAdmin The initial default admin of the stablecoin.
    /// @param salt            Salt for deterministic address derivation.
    ///
    /// @return The deterministic stablecoin address.
    function computeAddressB20(
        string calldata name,
        string calldata symbol,
        string calldata currency,
        address stablecoinAdmin,
        bytes32 salt
    ) external view returns (address) {
        return StdPrecompiles.B20_FACTORY
            .getB20Address(
                IB20Factory.B20Variant.STABLECOIN,
                address(this),
                _deriveB20Salt({
                    name: name, symbol: symbol, currency: currency, stablecoinAdmin: stablecoinAdmin, salt: salt
                })
            );
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
    ///
    /// @param name            Token name.
    /// @param symbol          Token symbol.
    /// @param decimals        Token decimal places.
    /// @param stablecoinAdmin The initial default admin of the deployed {Stablecoin}.
    ///
    /// @return The packed creation bytecode ready for use with CREATE2.
    function _bytecode(string calldata name, string calldata symbol, uint8 decimals, address stablecoinAdmin)
        private
        view
        returns (bytes memory)
    {
        bytes memory data = abi.encodeCall(Stablecoin.initialize, (name, symbol, decimals, stablecoinAdmin));
        return abi.encodePacked(type(MutableBeaconProxy).creationCode, abi.encode(BEACON, data));
    }

    /// @notice Derives the B-20 salt from the token configuration and caller-provided salt.
    function _deriveB20Salt(
        string calldata name,
        string calldata symbol,
        string calldata currency,
        address stablecoinAdmin,
        bytes32 salt
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(name, symbol, currency, stablecoinAdmin, salt));
    }
}
