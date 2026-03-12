// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyFactoryTest} from "test/lib/OverrideableBeaconProxyFactoryTest.sol";

contract OverrideableBeaconProxyFactoryBeaconTest is OverrideableBeaconProxyFactoryTest {
    /// @notice Verifies beacon() returns the address stored during initialization.
    /// @dev The ERC-7201 factory storage must preserve the beacon address set in initialize.
    function test_beacon_returnsStoredBeacon() public view {
        assertEq(factory.beacon(), address(beacon));
    }
}
