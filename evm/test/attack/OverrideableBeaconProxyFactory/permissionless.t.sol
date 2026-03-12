// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {OverrideableBeaconProxyFactoryTest} from "test/lib/OverrideableBeaconProxyFactoryTest.sol";

contract OverrideableBeaconProxyFactoryPermissionlessTest is OverrideableBeaconProxyFactoryTest {
    /// @notice Verifies a caller without DEPLOYER_ROLE cannot deploy proxies through the factory.
    /// @dev Permissionless: an attacker cannot create proxies pointing at the shared beacon under an arbitrary admin.
    function test_attack_unauthorizedCallerCannotDeploy(address caller) public {
        vm.assume(caller != admin && caller != deployer);
        bytes32 deployerRole = factory.DEPLOYER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, deployerRole)
        );
        _deploy(caller, bytes32(0), alice, "");
    }
}
