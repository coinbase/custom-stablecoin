// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

/// @dev Minimal interface for making a delegated call through the proxy.
interface IVersion {
    function version() external pure returns (uint256);
}

contract OverrideableBeaconProxyBenchmarkTest is OverrideableBeaconProxyTest {
    /// @notice Measures gas for a delegated call routed through the beacon (no override set).
    /// @dev Hot path: _implementation() reads the empty slot, falls through to beacon.implementation(),
    ///      then delegatecalls. This is the default resolution path for all unoverridden proxies.
    function test_benchmark_delegateCall_viaBeacon() public {
        uint256 gasBefore = gasleft();
        uint256 v = IVersion(address(proxy)).version();
        uint256 gasUsed = gasBefore - gasleft();
        assertTrue(v > 0); // prevent dead-code elimination
        emit log_named_uint("gas:delegateCall_viaBeacon", gasUsed);
    }

    /// @notice Measures gas for a delegated call routed through a direct implementation override.
    /// @dev Hot path: _implementation() reads a non-zero slot and returns immediately, skipping the
    ///      beacon entirely. Expected to be cheaper than the beacon path by one external call.
    function test_benchmark_delegateCall_viaOverride() public {
        _setImplementationOverride(address(implV2));
        uint256 gasBefore = gasleft();
        uint256 v = IVersion(address(proxy)).version();
        uint256 gasUsed = gasBefore - gasleft();
        assertTrue(v > 0); // prevent dead-code elimination
        emit log_named_uint("gas:delegateCall_viaOverride", gasUsed);
    }
}
