// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {MockBeacon} from "test/lib/mocks/MockBeacon.sol";
import {MockImplementation} from "test/lib/mocks/MockImplementation.sol";
import {MockImplementationV2} from "test/lib/mocks/MockImplementationV2.sol";

contract OverrideableBeaconProxyTest is Test {
    // ── Actors ──────────────────────────────────────────────────
    address internal proxyAdmin = makeAddr("proxyAdmin");
    address internal newAdmin = makeAddr("newAdmin");
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    // ── Contracts ───────────────────────────────────────────────
    MockImplementation internal impl;
    MockImplementationV2 internal implV2;
    MockBeacon internal beacon;
    OverrideableBeaconProxy internal proxy;

    // ── Setup ───────────────────────────────────────────────────

    function setUp() public virtual {
        impl = new MockImplementation();
        implV2 = new MockImplementationV2();
        beacon = new MockBeacon(address(impl));
        proxy = new OverrideableBeaconProxy(address(beacon), proxyAdmin, "");

        vm.label(address(impl), "MockImplementation");
        vm.label(address(implV2), "MockImplementationV2");
        vm.label(address(beacon), "MockBeacon");
        vm.label(address(proxy), "OverrideableBeaconProxy");
        vm.label(proxyAdmin, "proxyAdmin");
        vm.label(newAdmin, "newAdmin");
        vm.label(alice, "alice");
        vm.label(attacker, "attacker");
    }

    // ── Helpers ─────────────────────────────────────────────────

    /// @dev Deploys a fresh proxy with custom arguments. Used by constructor tests.
    function _deployProxy(address admin, bytes memory data) internal returns (OverrideableBeaconProxy) {
        return new OverrideableBeaconProxy(address(beacon), admin, data);
    }

    /// @dev Sets the implementation override as the given caller.
    function _setImplementationOverride(address caller, address implementation) internal {
        vm.prank(caller);
        proxy.setImplementationOverride(implementation);
    }

    /// @dev Sets the implementation override as the proxy admin (default caller).
    function _setImplementationOverride(address implementation) internal {
        _setImplementationOverride(proxyAdmin, implementation);
    }

    /// @dev Initiates a proxy admin transfer as the given caller.
    function _transferProxyAdmin(address caller, address newAdmin_) internal {
        vm.prank(caller);
        proxy.transferProxyAdmin(newAdmin_);
    }

    /// @dev Initiates a proxy admin transfer as the current proxy admin (default caller).
    function _transferProxyAdmin(address newAdmin_) internal {
        _transferProxyAdmin(proxyAdmin, newAdmin_);
    }

    /// @dev Accepts the proxy admin role as the given caller.
    function _acceptProxyAdmin(address caller) internal {
        vm.prank(caller);
        proxy.acceptProxyAdmin();
    }
}
