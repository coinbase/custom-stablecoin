// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract OverrideableBeaconProxyPermissionlessTest is OverrideableBeaconProxyTest {
    /// @notice Verifies no arbitrary caller can set the implementation override without being the admin.
    /// @dev Degrees of freedom: attacker controls the implementation address; UnauthorizedProxyAdmin must always fire.
    function test_attack_nonAdminCannotSetImplementation(address caller) public {
        vm.assume(caller != proxyAdmin);
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.UnauthorizedProxyAdmin.selector, caller));
        _setImplementationOverride(caller, address(implV2));
    }

    /// @notice Verifies no arbitrary caller can initiate an admin transfer without being the admin.
    /// @dev Degrees of freedom: attacker controls the target newAdmin address; must always revert.
    function test_attack_nonAdminCannotTransferAdmin(address caller) public {
        vm.assume(caller != proxyAdmin);
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.UnauthorizedProxyAdmin.selector, caller));
        _transferProxyAdmin(caller, attacker);
    }

    /// @notice Verifies acceptProxyAdmin cannot be called by any address other than the pending admin.
    /// @dev Degrees of freedom: attacker calls acceptProxyAdmin after a transfer is initiated; must always revert.
    function test_attack_nonPendingAdminCannotAccept(address caller) public {
        _transferProxyAdmin(alice); // set pending admin to alice
        vm.assume(caller != alice);
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.UnauthorizedProxyAdmin.selector, caller));
        _acceptProxyAdmin(caller);
    }

    /// @notice Verifies the constructor prevents deployment with a zero admin, closing the zero-admin attack vector.
    /// @dev A zero admin would make the proxy permanently locked; constructor must reject it unconditionally.
    function test_attack_zeroAddressAdminPrevented() public {
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.InvalidProxyAdmin.selector, address(0)));
        _deployProxy(address(0), "");
    }
}
