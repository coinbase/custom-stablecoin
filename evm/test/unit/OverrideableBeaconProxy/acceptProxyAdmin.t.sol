// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract OverrideableBeaconProxyAcceptProxyAdminTest is OverrideableBeaconProxyTest {
    function setUp() public override {
        super.setUp();
        _transferProxyAdmin(newAdmin);
    }

    /// @notice Verifies acceptProxyAdmin reverts for any caller that is not the pending admin.
    /// @dev UnauthorizedProxyAdmin must fire for all addresses except the exact pending admin.
    function test_acceptProxyAdmin_revert_notPendingAdmin(address caller) public {
        vm.assume(caller != newAdmin);
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.UnauthorizedProxyAdmin.selector, caller));
        _acceptProxyAdmin(caller);
    }

    /// @notice Verifies acceptProxyAdmin reverts when no transfer is in progress (pending admin is zero).
    /// @dev address(0) is never a valid msg.sender, so the check always fails when pending is unset.
    function test_acceptProxyAdmin_revert_noPendingTransfer(address caller) public {
        _transferProxyAdmin(address(0)); // cancel pending transfer
        vm.assume(caller != address(0));
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.UnauthorizedProxyAdmin.selector, caller));
        _acceptProxyAdmin(caller);
    }

    /// @notice Verifies acceptProxyAdmin promotes the caller to the proxy admin role.
    /// @dev proxyAdmin() must return the former pending admin address after a successful acceptance.
    function test_acceptProxyAdmin_success_setsNewAdmin() public {
        _acceptProxyAdmin(newAdmin);
        assertEq(proxy.proxyAdmin(), newAdmin);
    }

    /// @notice Verifies acceptProxyAdmin clears the pending admin slot after the transfer completes.
    /// @dev pendingProxyAdmin() must return address(0) once the two-step transfer is finalized.
    function test_acceptProxyAdmin_success_clearsPendingAdmin() public {
        _acceptProxyAdmin(newAdmin);
        assertEq(proxy.pendingProxyAdmin(), address(0));
    }

    /// @notice Verifies acceptProxyAdmin emits AdminChanged with the old and new admin addresses.
    /// @dev Event integrity: block explorers track admin changes via AdminChanged; both addresses must be correct.
    function test_acceptProxyAdmin_success_emitsAdminChanged() public {
        vm.expectEmit(false, false, false, true, address(proxy));
        emit IERC1967.AdminChanged(proxyAdmin, newAdmin);
        _acceptProxyAdmin(newAdmin);
    }
}
