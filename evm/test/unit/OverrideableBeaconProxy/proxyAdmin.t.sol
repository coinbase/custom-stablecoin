// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract OverrideableBeaconProxyProxyAdminTest is OverrideableBeaconProxyTest {
    /// @notice Verifies proxyAdmin returns the admin address set during construction.
    /// @dev Confirms the ERC-1967 admin slot was correctly written by the constructor.
    function test_proxyAdmin_returnsInitialAdmin() public view {
        assertEq(proxy.proxyAdmin(), proxyAdmin);
    }

    /// @notice Verifies proxyAdmin reflects the updated admin only after acceptProxyAdmin completes.
    /// @dev State must not change after transferProxyAdmin alone; two-step requires acceptance first.
    function test_proxyAdmin_returnsUpdatedAdminAfterTransfer() public {
        _transferProxyAdmin(newAdmin);
        assertEq(proxy.proxyAdmin(), proxyAdmin); // unchanged until accepted

        _acceptProxyAdmin(newAdmin);
        assertEq(proxy.proxyAdmin(), newAdmin);
    }
}
