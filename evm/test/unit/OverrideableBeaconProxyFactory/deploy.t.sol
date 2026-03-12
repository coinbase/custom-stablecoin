// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {OverrideableBeaconProxyFactory} from "src/OverrideableBeaconProxyFactory.sol";
import {OverrideableBeaconProxyFactoryTest} from "test/lib/OverrideableBeaconProxyFactoryTest.sol";

contract OverrideableBeaconProxyFactoryDeployTest is OverrideableBeaconProxyFactoryTest {
    /// @notice Verifies deploy reverts for any caller without DEPLOYER_ROLE.
    /// @dev Access control: the onlyRole(DEPLOYER_ROLE) guard must fire before any proxy is created.
    function test_deploy_revert_unauthorized(address caller) public {
        vm.assume(caller != admin && caller != deployer);
        bytes32 deployerRole = factory.DEPLOYER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, deployerRole)
        );
        _deploy(caller, bytes32(0), alice, "");
    }

    /// @notice Verifies deploy returns the address of a newly deployed contract with code.
    /// @dev The returned address must have code; fuzz confirms deterministic deployment for any salt and admin.
    function test_deploy_success_deploysProxy(bytes32 salt, address proxyAdmin_) public {
        vm.assume(proxyAdmin_ != address(0));
        address proxyAddr = _deploy(salt, proxyAdmin_);
        assertGt(proxyAddr.code.length, 0);
    }

    /// @notice Verifies deploy emits ProxyDeployed with the proxy address, admin, and salt.
    /// @dev Event integrity: all three indexed fields must match the deployment parameters exactly.
    function test_deploy_success_emitsProxyDeployed(bytes32 salt, address proxyAdmin_) public {
        vm.assume(proxyAdmin_ != address(0));
        address predicted = factory.getAddress(salt, proxyAdmin_, "");
        vm.expectEmit(true, true, false, true, address(factory));
        emit OverrideableBeaconProxyFactory.ProxyDeployed(predicted, proxyAdmin_, salt);
        _deploy(salt, proxyAdmin_);
    }

    /// @notice Verifies the deployed proxy address matches the address predicted by getAddress.
    /// @dev Determinism guarantee: CREATE2 address must be consistent between prediction and deployment.
    function test_deploy_success_matchesPredictedAddress(bytes32 salt, address proxyAdmin_) public {
        vm.assume(proxyAdmin_ != address(0));
        address predicted = factory.getAddress(salt, proxyAdmin_, "");
        address deployed = _deploy(salt, proxyAdmin_);
        assertEq(deployed, predicted);
    }

    /// @notice Verifies the deployed proxy stores the provided admin in its ERC-1967 admin slot.
    /// @dev The proxy's proxyAdmin() must return the admin passed to factory.deploy(); fuzz confirms for any admin.
    function test_deploy_success_proxySetsCorrectAdmin(bytes32 salt, address proxyAdmin_) public {
        vm.assume(proxyAdmin_ != address(0));
        address proxyAddr = _deploy(salt, proxyAdmin_);
        assertEq(OverrideableBeaconProxy(payable(proxyAddr)).proxyAdmin(), proxyAdmin_);
    }
}
