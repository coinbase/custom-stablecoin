// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract OverrideableBeaconProxyPendingProxyAdminTest is OverrideableBeaconProxyTest {
    /// @notice Verifies pendingProxyAdmin returns address(0) when no transfer has been initiated.
    /// @dev The ERC-7201 pending admin slot must be empty after construction.
    function test_pendingProxyAdmin_returnsZeroDefault() public view {
        assertEq(proxy.pendingProxyAdmin(), address(0));
    }

    /// @notice Verifies pendingProxyAdmin returns the address written by transferProxyAdmin.
    /// @dev The view must reflect the exact address stored in the ERC-7201 pending admin slot.
    function test_pendingProxyAdmin_returnsPendingAdmin(address newAdmin_) public {
        _transferProxyAdmin(newAdmin_);
        assertEq(proxy.pendingProxyAdmin(), newAdmin_);
    }
}
