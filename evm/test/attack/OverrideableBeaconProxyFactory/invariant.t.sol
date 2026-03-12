// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyFactoryTest} from "test/lib/OverrideableBeaconProxyFactoryTest.sol";

/// @dev Stateful invariant tests for OverrideableBeaconProxyFactory.
///      Implementation note: a handler wrapping factory functions is required because
///      Foundry cannot introspect functions through a UUPS proxy via targetContract directly.
///      The handler should expose deploy() and any role-management calls so the fuzzer
///      can reach interesting states while the invariant checks beacon immutability.
contract OverrideableBeaconProxyFactoryInvariantTest is OverrideableBeaconProxyFactoryTest {
    /// @notice Invariant: the beacon address stored at initialization never changes.
    /// @dev The beacon has no setter; no function sequence should be able to overwrite it.
    function invariant_beaconIsImmutable() public view {
        assertEq(factory.beacon(), address(beacon));
    }
}
