// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract AdminTransferLifecycleTest is OverrideableBeaconProxyTest {
    /// @notice Verifies the full two-step admin transfer lifecycle: initiate → accept → new admin is active.
    /// @dev Integration: proxyAdmin() must equal newAdmin after acceptance; newAdmin can call onlyProxyAdmin functions.
    function test_integration_fullAdminTransferLifecycle() public {
        _transferProxyAdmin(newAdmin);
        assertEq(proxy.proxyAdmin(), proxyAdmin); // unchanged mid-flight

        _acceptProxyAdmin(newAdmin);
        assertEq(proxy.proxyAdmin(), newAdmin);
        assertEq(proxy.pendingProxyAdmin(), address(0));
    }

    /// @notice Verifies a pending transfer can be cancelled by setting pending to address(0).
    /// @dev After cancellation the original admin retains control and pendingProxyAdmin() returns zero.
    function test_integration_cancelPendingTransfer() public {
        _transferProxyAdmin(newAdmin);
        _transferProxyAdmin(address(0)); // cancel

        assertEq(proxy.pendingProxyAdmin(), address(0));
        assertEq(proxy.proxyAdmin(), proxyAdmin); // original admin still in control
    }

    /// @notice Verifies the old admin cannot call onlyProxyAdmin functions after a completed transfer.
    /// @dev Security: the former admin must be fully ejected; UnauthorizedProxyAdmin must fire for all their calls.
    function test_integration_oldAdminCannotActAfterTransfer() public {
        _transferProxyAdmin(newAdmin);
        _acceptProxyAdmin(newAdmin);

        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.UnauthorizedProxyAdmin.selector, proxyAdmin));
        _setImplementationOverride(proxyAdmin, address(implV2));
    }

    /// @notice Verifies the new admin can call all onlyProxyAdmin functions after a completed transfer.
    /// @dev Confirms the new admin has full operational access: setImplementationOverride and transferProxyAdmin.
    function test_integration_newAdminCanCallProtectedFunctions() public {
        _transferProxyAdmin(newAdmin);
        _acceptProxyAdmin(newAdmin);

        // New admin can set the implementation override.
        _setImplementationOverride(newAdmin, address(implV2));
        assertEq(proxy.implementationOverride(), address(implV2));

        // New admin can initiate a further admin transfer.
        _transferProxyAdmin(newAdmin, alice);
        assertEq(proxy.pendingProxyAdmin(), alice);
    }
}
