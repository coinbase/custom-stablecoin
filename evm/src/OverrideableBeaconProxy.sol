// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

/// @title OverrideableBeaconProxy
/// @author Coinbase
/// @notice A {BeaconProxy} that allows a proxy-level admin to set a direct
/// implementation override (opt-out), bypassing the beacon entirely for
/// this proxy instance.
///
/// @dev Resolution order in {_implementation}:
///   1. If the ERC-1967 implementation slot is set, use it directly (opt-out).
///   2. Otherwise, query the beacon for the shared implementation (default).
///
/// The proxy admin address is stored in the ERC-1967 admin slot for
/// compatibility with block explorers and standard tooling. The pending
/// admin (for two-step transfers) is stored in an ERC-7201 namespaced
/// slot to avoid collisions. Admin functions use unique selectors
/// (`proxyAdmin`, `transferProxyAdmin`, etc.) to avoid clashing with
/// selectors the implementation may expose.
contract OverrideableBeaconProxy is BeaconProxy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for the OverrideableBeaconProxy.
    /// @custom:storage-location erc7201:coinbase.storage.OverrideableBeaconProxy
    struct OverrideableBeaconProxyStorage {
        /// @dev The pending proxy admin address, set during a two-step transfer.
        address pendingAdmin;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.OverrideableBeaconProxy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OVERRIDEABLE_BEACON_PROXY_STORAGE_LOCATION =
        0x48bf781b3e066d6328e65796599f6ef321293b13fff4a961d8e8d5252f809800;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a proxy admin transfer is initiated.
    ///
    /// @param previousAdmin The current admin initiating the transfer.
    /// @param newAdmin      The pending admin that must accept.
    event ProxyAdminTransferStarted(address indexed previousAdmin, address indexed newAdmin);

    /// @notice Emitted when the implementation override is cleared, returning to beacon behavior.
    event ImplementationOverrideCleared();

    /// @notice Thrown when the provided implementation address has no code.
    ///
    /// @param implementation The invalid implementation address.
    error InvalidImplementation(address implementation);

    /// @notice Thrown when the provided admin address is invalid (e.g. zero address).
    ///
    /// @param admin The invalid admin address.
    error InvalidProxyAdmin(address admin);

    /// @notice Thrown when the caller is not the proxy admin.
    ///
    /// @param caller The unauthorized caller.
    error UnauthorizedProxyAdmin(address caller);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyProxyAdmin() {
        _checkProxyAdmin();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deploys the proxy pointing at `beacon` with `admin` as the initial proxy admin.
    ///
    /// @param beacon The beacon contract supplying the shared implementation address.
    /// @param admin  The initial proxy admin; must not be the zero address.
    /// @param data   Optional calldata forwarded to the implementation via delegatecall on deployment.
    constructor(address beacon, address admin, bytes memory data) payable BeaconProxy(beacon, data) {
        if (admin == address(0)) revert InvalidProxyAdmin({admin: address(0)});
        StorageSlot.getAddressSlot(ERC1967Utils.ADMIN_SLOT).value = admin;
        emit IERC1967.AdminChanged(address(0), admin);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          RECEIVE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    receive() external payable {
        _fallback();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets a direct implementation for this proxy, opting out of the beacon.
    ///
    /// @dev Pass `address(0)` to clear the override and return to beacon behavior.
    ///
    /// @param implementation The implementation address to set, or `address(0)` to clear.
    function setImplementationOverride(address implementation) external onlyProxyAdmin {
        if (implementation != address(0) && implementation.code.length == 0) {
            revert InvalidImplementation({implementation: implementation});
        }
        StorageSlot.getAddressSlot(ERC1967Utils.IMPLEMENTATION_SLOT).value = implementation;
        if (implementation != address(0)) {
            emit IERC1967.Upgraded(implementation);
        } else {
            emit ImplementationOverrideCleared();
        }
    }

    /// @notice Starts a two-step transfer of the proxy admin role to `newAdmin`.
    ///
    /// @dev Setting `newAdmin` to `address(0)` cancels a pending transfer.
    ///
    /// @param newAdmin The address to transfer the proxy admin role to.
    function transferProxyAdmin(address newAdmin) external onlyProxyAdmin {
        _getOverrideableBeaconProxyStorage().pendingAdmin = newAdmin;
        emit ProxyAdminTransferStarted({previousAdmin: proxyAdmin(), newAdmin: newAdmin});
    }

    /// @notice Accepts the proxy admin role. Must be called by the pending admin.
    function acceptProxyAdmin() external {
        OverrideableBeaconProxyStorage storage $ = _getOverrideableBeaconProxyStorage();
        if (msg.sender != $.pendingAdmin) revert UnauthorizedProxyAdmin({caller: msg.sender});
        address oldAdmin = ERC1967Utils.getAdmin();
        StorageSlot.getAddressSlot(ERC1967Utils.ADMIN_SLOT).value = msg.sender;
        delete $.pendingAdmin;
        emit IERC1967.AdminChanged(oldAdmin, msg.sender);
    }

    /// @notice Returns the current implementation override, or `address(0)` if using the beacon.
    ///
    /// @return The override implementation address.
    function implementationOverride() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the current proxy admin address.
    ///
    /// @return The proxy admin address.
    function proxyAdmin() public view returns (address) {
        return ERC1967Utils.getAdmin();
    }

    /// @notice Returns the pending proxy admin address, or `address(0)` if none.
    ///
    /// @return The pending proxy admin address.
    function pendingProxyAdmin() public view returns (address) {
        return _getOverrideableBeaconProxyStorage().pendingAdmin;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Reverts if the caller is not the proxy admin.
    function _checkProxyAdmin() internal view {
        if (msg.sender != proxyAdmin()) revert UnauthorizedProxyAdmin({caller: msg.sender});
    }

    /// @notice Returns the active implementation address.
    ///
    /// @dev Returns the ERC-1967 implementation slot if set (opt-out override),
    /// otherwise falls back to querying the beacon.
    ///
    /// @return The implementation address to delegate calls to.
    function _implementation() internal view override returns (address) {
        address directImpl = ERC1967Utils.getImplementation();
        if (directImpl != address(0)) {
            return directImpl;
        }
        return IBeacon(_getBeacon()).implementation();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns a storage pointer to the ERC-7201 namespaced pending admin layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getOverrideableBeaconProxyStorage() private pure returns (OverrideableBeaconProxyStorage storage $) {
        assembly {
            $.slot := OVERRIDEABLE_BEACON_PROXY_STORAGE_LOCATION
        }
    }
}
