// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

/**
 * @dev A {BeaconProxy} that allows a proxy-level admin to set a direct
 * implementation override (opt-out), bypassing the beacon entirely for
 * this proxy instance.
 *
 * Resolution order in {_implementation}:
 *   1. If the ERC-1967 implementation slot is set, use it directly (opt-out).
 *   2. Otherwise, query the beacon for the shared implementation (default).
 *
 * Admin state is stored in an ERC-7201 namespaced slot so it cannot
 * collide with implementation storage or ERC-1967 slots. Admin functions
 * use unique selectors (`proxyAdmin`, `transferProxyAdmin`, etc.) to
 * avoid clashing with selectors the implementation may expose.
 */
contract OverrideableBeaconProxy is BeaconProxy {
    // -------------------------------------------------------------------------
    // ERC-7201 namespaced storage
    // -------------------------------------------------------------------------

    /// @custom:storage-location erc7201:coinbase.storage.OverrideableBeaconProxy
    struct ProxyAdminStorage {
        address admin;
        address pendingAdmin;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.OverrideableBeaconProxy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PROXY_ADMIN_STORAGE_LOCATION =
        0x48bf781b3e066d6328e65796599f6ef321293b13fff4a961d8e8d5252f809800;

    function _getProxyAdminStorage() private pure returns (ProxyAdminStorage storage $) {
        assembly {
            $.slot := PROXY_ADMIN_STORAGE_LOCATION
        }
    }

    // -------------------------------------------------------------------------
    // Events / errors
    // -------------------------------------------------------------------------

    event ProxyAdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event ProxyAdminTransferStarted(address indexed previousAdmin, address indexed newAdmin);
    event ImplementationOverrideSet(address indexed implementation);

    error InvalidImplementation(address implementation);
    error InvalidProxyAdmin(address admin);
    error UnauthorizedProxyAdmin(address caller);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyProxyAdmin() {
        _checkProxyAdmin();
        _;
    }

    function _checkProxyAdmin() internal view {
        if (msg.sender != proxyAdmin()) revert UnauthorizedProxyAdmin(msg.sender);
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address beacon, address admin, bytes memory data)
        payable
        BeaconProxy(beacon, data)
    {
        if (admin == address(0)) revert InvalidProxyAdmin(address(0));
        _getProxyAdminStorage().admin = admin;
        emit ProxyAdminTransferred(address(0), admin);
    }

    // -------------------------------------------------------------------------
    // Implementation override
    // -------------------------------------------------------------------------

    /**
     * @dev Sets a direct implementation for this proxy, opting out of the beacon.
     *      Pass `address(0)` to clear the override and return to beacon behavior.
     */
    function setImplementationOverride(address implementation) external onlyProxyAdmin {
        if (implementation != address(0) && implementation.code.length == 0) {
            revert InvalidImplementation(implementation);
        }
        StorageSlot.getAddressSlot(ERC1967Utils.IMPLEMENTATION_SLOT).value = implementation;
        emit ImplementationOverrideSet(implementation);
    }

    /**
     * @dev Returns the current override, or `address(0)` if using the beacon.
     */
    function implementationOverride() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    // -------------------------------------------------------------------------
    // Two-step admin transfer
    // -------------------------------------------------------------------------

    function proxyAdmin() public view returns (address) {
        return _getProxyAdminStorage().admin;
    }

    function pendingProxyAdmin() public view returns (address) {
        return _getProxyAdminStorage().pendingAdmin;
    }

    /**
     * @dev Starts a two-step transfer of proxy admin to `newAdmin`.
     *      Setting `newAdmin` to `address(0)` cancels a pending transfer.
     */
    function transferProxyAdmin(address newAdmin) external onlyProxyAdmin {
        _getProxyAdminStorage().pendingAdmin = newAdmin;
        emit ProxyAdminTransferStarted(proxyAdmin(), newAdmin);
    }

    /**
     * @dev The pending admin accepts the proxy admin role.
     */
    function acceptProxyAdmin() external {
        ProxyAdminStorage storage $ = _getProxyAdminStorage();
        if (msg.sender != $.pendingAdmin) revert UnauthorizedProxyAdmin(msg.sender);
        address oldAdmin = $.admin;
        $.admin = msg.sender;
        delete $.pendingAdmin;
        emit ProxyAdminTransferred(oldAdmin, msg.sender);
    }

    // -------------------------------------------------------------------------
    // Fallback / receive
    // -------------------------------------------------------------------------

    receive() external payable {
        _fallback();
    }

    function _implementation() internal view override returns (address) {
        address directImpl = ERC1967Utils.getImplementation();
        if (directImpl != address(0)) {
            return directImpl;
        }
        return IBeacon(_getBeacon()).implementation();
    }
}
