// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract OverrideableBeaconProxySetImplementationOverrideTest is OverrideableBeaconProxyTest {
    /// @notice Verifies setImplementationOverride reverts for any non-admin caller.
    /// @dev UnauthorizedProxyAdmin must fire before any storage write; fuzz confirms for all non-admin addresses.
    function test_setImplementationOverride_revert_unauthorized(address caller) public {
        vm.assume(caller != proxyAdmin);
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.UnauthorizedProxyAdmin.selector, caller));
        _setImplementationOverride(caller, address(implV2));
    }

    /// @notice Verifies setImplementationOverride reverts when a non-zero address with no deployed code is provided.
    /// @dev InvalidImplementation prevents pointing the proxy at an EOA or a self-destructed contract.
    function test_setImplementationOverride_revert_noCode(address implementation) public {
        vm.assume(implementation != address(0));
        vm.assume(implementation.code.length == 0);
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.InvalidImplementation.selector, implementation));
        _setImplementationOverride(implementation);
    }

    /// @notice Verifies setImplementationOverride writes the address to the ERC-1967 implementation slot.
    /// @dev implementationOverride() must return the newly set address after a successful call.
    function test_setImplementationOverride_success_setsSlot() public {
        _setImplementationOverride(address(implV2));
        assertEq(proxy.implementationOverride(), address(implV2));
    }

    /// @notice Verifies setImplementationOverride emits Upgraded with the new implementation address.
    /// @dev Event integrity: standard tooling relies on Upgraded to track implementation changes.
    function test_setImplementationOverride_success_emitsUpgraded() public {
        vm.expectEmit(true, false, false, false, address(proxy));
        emit IERC1967.Upgraded(address(implV2));
        _setImplementationOverride(address(implV2));
    }

    /// @notice Verifies passing address(0) clears the ERC-1967 implementation slot.
    /// @dev Clearing the slot returns the proxy to beacon-mode delegation; implementationOverride() returns zero.
    function test_setImplementationOverride_success_clearSlot() public {
        _setImplementationOverride(address(implV2));
        _setImplementationOverride(address(0));
        assertEq(proxy.implementationOverride(), address(0));
    }

    /// @notice Verifies passing address(0) emits ImplementationOverrideCleared rather than Upgraded.
    /// @dev Event integrity: the clear path must emit the distinct clearing event, not the upgrade event.
    function test_setImplementationOverride_success_emitsOverrideCleared() public {
        _setImplementationOverride(address(implV2));
        vm.expectEmit(false, false, false, false, address(proxy));
        emit OverrideableBeaconProxy.ImplementationOverrideCleared();
        _setImplementationOverride(address(0));
    }

    /// @notice Verifies that address(0) bypasses the code-length check without reverting.
    /// @dev Zero is the sentinel for clearing the override; it must not trigger InvalidImplementation.
    function test_setImplementationOverride_success_zeroBypassesCodeCheck() public {
        _setImplementationOverride(address(0));
        assertEq(proxy.implementationOverride(), address(0));
    }
}
