// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {OverrideableBeaconProxyTest} from "test/lib/OverrideableBeaconProxyTest.sol";

contract OverrideableBeaconProxyConstructorTest is OverrideableBeaconProxyTest {
    /// @notice Verifies the constructor reverts when admin is the zero address.
    /// @dev InvalidProxyAdmin(address(0)) must fire; a zero admin permanently bricks all onlyProxyAdmin functions.
    function test_constructor_revert_zeroAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(OverrideableBeaconProxy.InvalidProxyAdmin.selector, address(0)));
        _deployProxy(address(0), "");
    }

    /// @notice Verifies the constructor stores the provided admin in the ERC-1967 admin slot.
    /// @dev proxyAdmin() must return exactly the address passed at construction; fuzz confirms for any valid admin.
    function test_constructor_success_setsAdmin(address admin) public {
        vm.assume(admin != address(0));
        OverrideableBeaconProxy p = _deployProxy(admin, "");
        assertEq(p.proxyAdmin(), admin);
    }

    /// @notice Verifies the constructor emits AdminChanged with previousAdmin zero and newAdmin equal to admin.
    /// @dev Event integrity: block explorers track admins via AdminChanged; the initial emit must be correct.
    function test_constructor_success_emitsAdminChanged(address admin) public {
        vm.assume(admin != address(0));
        vm.expectEmit(false, false, false, true);
        emit IERC1967.AdminChanged(address(0), admin);
        _deployProxy(admin, "");
    }

    /// @notice Verifies no implementation override is active immediately after construction.
    /// @dev implementationOverride() must return address(0), indicating beacon-mode delegation is active.
    function test_constructor_success_noInitialOverride(address admin) public {
        vm.assume(admin != address(0));
        OverrideableBeaconProxy p = _deployProxy(admin, "");
        assertEq(p.implementationOverride(), address(0));
    }
}
