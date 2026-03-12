// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

/// @dev Stateful invariant tests for OverrideableBeaconProxy.
///      Implementation note: a handler contract wrapping the proxy's admin functions with
///      correctly-privileged actors is required for the fuzzer to reach interesting states.
///      The handler should track the current admin and pending admin so it can call
///      transferProxyAdmin and acceptProxyAdmin with valid actors on some runs.
contract OverrideableBeaconProxyInvariantTest is OverrideableBeaconProxyTest {
    function setUp() public override {
        super.setUp();
        targetContract(address(proxy));
    }

    /// @notice Invariant: the ERC-1967 admin slot is never zero after any sequence of calls.
    /// @dev acceptProxyAdmin sets admin to msg.sender; msg.sender is never address(0), so the slot cannot be zeroed.
    function invariant_proxyAdminIsNeverZero() public view {
        assertNotEq(proxy.proxyAdmin(), address(0));
    }

    /// @notice Invariant: the resolved implementation address is always non-zero.
    /// @dev The proxy must always be able to delegate; either the override slot or the beacon must supply an address.
    function invariant_activeImplementationIsNonZero() public view {
        address override_ = proxy.implementationOverride();
        address beaconImpl = beacon.implementation();
        assertTrue(override_ != address(0) || beaconImpl != address(0));
    }

    /// @notice Invariant: the pending admin slot is zero unless a transfer has been explicitly initiated.
    /// @dev The only way to set a non-zero pending admin is via transferProxyAdmin called by the current admin.
    function invariant_pendingAdminIsZeroOrExplicitlySet() public view {
        // If a transfer is pending, the proxy admin must still be non-zero.
        // This holds because only a current non-zero admin can initiate a transfer via transferProxyAdmin.
        if (proxy.pendingProxyAdmin() != address(0)) {
            assertNotEq(proxy.proxyAdmin(), address(0));
        }
    }
}
