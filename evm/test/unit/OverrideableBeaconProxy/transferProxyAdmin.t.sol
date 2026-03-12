// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract OverrideableBeaconProxyTransferProxyAdminTest is OverrideableBeaconProxyTest {
    /// @notice Verifies transferProxyAdmin reverts for any non-admin caller.
    /// @dev UnauthorizedProxyAdmin must fire before writing the pending admin slot; fuzz confirms for all callers.
    function test_transferProxyAdmin_revert_unauthorized(address caller) public {
        vm.assume(caller != proxyAdmin);
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.UnauthorizedProxyAdmin.selector, caller));
        _transferProxyAdmin(caller, newAdmin);
    }

    /// @notice Verifies transferProxyAdmin stores the provided address in the ERC-7201 pending admin slot.
    /// @dev pendingProxyAdmin() must return newAdmin_ immediately after the call; fuzz confirms for any address.
    function test_transferProxyAdmin_success_setsPendingAdmin(address newAdmin_) public {
        _transferProxyAdmin(newAdmin_);
        assertEq(proxy.pendingProxyAdmin(), newAdmin_);
    }

    /// @notice Verifies transferProxyAdmin emits ProxyAdminTransferStarted with the correct addresses.
    /// @dev Event integrity: previousAdmin must be the current admin; newAdmin must be the candidate.
    function test_transferProxyAdmin_success_emitsTransferStarted(address newAdmin_) public {
        vm.expectEmit(true, true, false, false, address(proxy));
        emit OverrideableBeaconProxy.ProxyAdminTransferStarted(proxyAdmin, newAdmin_);
        _transferProxyAdmin(newAdmin_);
    }

    /// @notice Verifies passing address(0) to transferProxyAdmin cancels a pending transfer.
    /// @dev Setting pending to zero is the documented cancellation mechanism; pendingProxyAdmin() must return zero.
    function test_transferProxyAdmin_success_cancelsPendingTransfer() public {
        _transferProxyAdmin(newAdmin);
        _transferProxyAdmin(address(0));
        assertEq(proxy.pendingProxyAdmin(), address(0));
    }
}
