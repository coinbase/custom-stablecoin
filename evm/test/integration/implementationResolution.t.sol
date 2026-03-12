// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

/// @dev Minimal interface for verifying which implementation the proxy delegates to.
interface IVersion {
    function version() external pure returns (uint256);
}

contract ImplementationResolutionTest is OverrideableBeaconProxyTest {
    /// @notice Verifies the proxy delegates calls to the beacon's implementation when no override is set.
    /// @dev Resolution order: with an empty implementation slot, _implementation() must fall through to beacon.
    function test_integration_beaconResolutionByDefault() public {
        assertEq(IVersion(address(proxy)).version(), 1);
    }

    /// @notice Verifies the proxy delegates calls to the override implementation when one is set.
    /// @dev Resolution order: a non-zero implementation slot takes priority; beacon is not consulted.
    function test_integration_overrideResolutionWhenSet() public {
        _setImplementationOverride(address(implV2));
        assertEq(IVersion(address(proxy)).version(), 2);
    }

    /// @notice Verifies the proxy returns to beacon-mode delegation after the override is cleared.
    /// @dev Clearing the slot (setImplementationOverride(address(0))) must restore beacon resolution.
    function test_integration_returnsToBeaconAfterClearingOverride() public {
        _setImplementationOverride(address(implV2));
        assertEq(IVersion(address(proxy)).version(), 2);

        _setImplementationOverride(address(0));
        assertEq(IVersion(address(proxy)).version(), 1);
    }

    /// @notice Verifies that upgrading the beacon's implementation is reflected in all unoverridden proxies.
    /// @dev Beacon upgrade: setting a new impl on MockBeacon must cause the proxy to delegate to the new impl.
    function test_integration_beaconUpgradeAffectsUnoverriddenProxy() public {
        assertEq(IVersion(address(proxy)).version(), 1);

        beacon.setImplementation(address(implV2));
        assertEq(IVersion(address(proxy)).version(), 2);
    }

    /// @notice Verifies that a proxy with an override is isolated from changes to the beacon's implementation.
    /// @dev Override isolation: the beacon can be upgraded without affecting a proxy that has opted out.
    function test_integration_beaconUpgradeDoesNotAffectOverriddenProxy() public {
        _setImplementationOverride(address(impl)); // pin proxy to v1
        beacon.setImplementation(address(implV2)); // upgrade beacon to v2
        assertEq(IVersion(address(proxy)).version(), 1); // proxy still delegates to v1 override
    }

    /// @notice Verifies that an existing override can be replaced with a different implementation.
    /// @dev Override upgrade: calling setImplementationOverride again switches delegation to the new address,
    ///      confirming the slot is fully mutable and not locked after the first write.
    function test_integration_overrideCanBeUpgradedToNewOverride() public {
        _setImplementationOverride(address(impl)); // set override to v1
        assertEq(IVersion(address(proxy)).version(), 1);

        _setImplementationOverride(address(implV2)); // upgrade override to v2
        assertEq(IVersion(address(proxy)).version(), 2);
    }
}
