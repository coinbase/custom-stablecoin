// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract OverrideableBeaconProxyImplementationOverrideTest is OverrideableBeaconProxyTest {
    /// @notice Verifies implementationOverride returns address(0) when no override has been set.
    /// @dev The ERC-1967 implementation slot must be empty immediately after construction.
    function test_implementationOverride_returnsZeroDefault() public view {
        assertEq(proxy.implementationOverride(), address(0));
    }

    /// @notice Verifies implementationOverride returns the address written by setImplementationOverride.
    /// @dev The view must reflect the exact address stored in the ERC-1967 implementation slot.
    function test_implementationOverride_returnsSetValue() public {
        _setImplementationOverride(address(implV2));
        assertEq(proxy.implementationOverride(), address(implV2));
    }
}
