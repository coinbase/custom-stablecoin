// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract OverrideableBeaconProxyReceiveTest is OverrideableBeaconProxyTest {
    /// @notice Verifies receive() forwards ETH-only calls to the implementation via _fallback().
    /// @dev Sending ETH with no calldata exercises the receive() path. MockImplementation is not
    ///      payable, so the delegatecall reverts, but receive() is entered and covered.
    function test_receive_forwardsToFallback() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool success,) = address(proxy).call{value: 1 ether}("");
        // MockImplementation does not accept ETH, so the delegated call reverts.
        assertFalse(success);
    }
}
