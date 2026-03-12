// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {OverrideableBeaconProxyFactory} from "src/OverrideableBeaconProxyFactory.sol";
import {OverrideableBeaconProxyFactoryTest} from "test/lib/OverrideableBeaconProxyFactoryTest.sol";

contract OverrideableBeaconProxyFactoryUpgradeToAndCallTest is OverrideableBeaconProxyFactoryTest {
    /// @notice Verifies the default admin can upgrade the factory implementation via upgradeToAndCall.
    /// @dev _authorizeUpgrade gates on DEFAULT_ADMIN_ROLE; a successful upgrade preserves factory state.
    function test_upgradeToAndCall_success_adminCanUpgrade() public {
        OverrideableBeaconProxyFactory newImpl = new OverrideableBeaconProxyFactory();
        vm.prank(admin);
        factory.upgradeToAndCall(address(newImpl), "");
        // Factory state is preserved after the upgrade.
        assertEq(factory.beacon(), address(beacon));
    }

    /// @notice Verifies upgradeToAndCall reverts for any caller without DEFAULT_ADMIN_ROLE.
    /// @dev _authorizeUpgrade's onlyRole guard must fire before the implementation is swapped.
    function test_upgradeToAndCall_revert_unauthorized(address caller) public {
        vm.assume(caller != admin);
        OverrideableBeaconProxyFactory newImpl = new OverrideableBeaconProxyFactory();
        bytes32 adminRole = factory.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, adminRole)
        );
        vm.prank(caller);
        factory.upgradeToAndCall(address(newImpl), "");
    }
}
