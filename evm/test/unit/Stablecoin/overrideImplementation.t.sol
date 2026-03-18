// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";
import {Stablecoin} from "src/Stablecoin.sol";

contract StablecoinExitBeaconTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies exitBeacon reverts for any caller without DEFAULT_ADMIN_ROLE
    /// @dev Access control: onlyRole(DEFAULT_ADMIN_ROLE) must reject all unauthorized callers
    function test_exitBeacon_revert_unauthorized(address caller) public {
        vm.assume(!stablecoin.hasRole(stablecoin.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.overrideImplementation(address(stablecoinImpl), "");
    }

    /// @notice Verifies exitBeacon reverts when newImplementation is the zero address
    /// @dev InvalidImplementation: zero address has no code; must be rejected before the slot write
    function test_exitBeacon_revert_invalidImplementation_zero() public {
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(0)));
        vm.prank(admin);
        stablecoin.overrideImplementation(address(0), "");
    }

    /// @notice Verifies exitBeacon reverts when newImplementation points to an address with no code
    /// @dev InvalidImplementation: code.length == 0 check prevents pointing at EOAs or empty addresses
    function test_exitBeacon_revert_invalidImplementation_noCode(address impl) public {
        vm.assume(impl != address(0));
        vm.assume(impl.code.length == 0);
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, impl));
        vm.prank(admin);
        stablecoin.overrideImplementation(impl, "");
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies exitBeacon writes the implementation slot so the proxy bypasses the beacon
    /// @dev One-way opt-out: after exitBeacon, upgrading the beacon does not affect this proxy
    function test_exitBeacon_success_bypassesBeacon() public {
        // Set proxy to use stablecoinImpl directly
        vm.prank(admin);
        stablecoin.overrideImplementation(address(stablecoinImpl), "");

        // The ERC-1967 implementation slot should now be set
        bytes32 slotValue = vm.load(address(proxy), ERC1967Utils.IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(slotValue))), address(stablecoinImpl));

        // Upgrade beacon to a new impl — proxy should ignore this
        Stablecoin newImpl = new Stablecoin();
        beacon.upgradeTo(address(newImpl));
        assertEq(beacon.implementation(), address(newImpl));

        // Proxy override slot still points at stablecoinImpl, not newImpl
        slotValue = vm.load(address(proxy), ERC1967Utils.IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(slotValue))), address(stablecoinImpl));

        // Proxy still functions correctly
        assertEq(stablecoin.name(), TOKEN_NAME);
    }

    /// @notice Verifies exitBeacon emits the Upgraded event with the new implementation address
    /// @dev Event integrity: IERC1967.Upgraded must be emitted so indexers track the override
    function test_exitBeacon_success_emitsUpgraded() public {
        vm.expectEmit(true, false, false, false);
        emit IERC1967.Upgraded(address(stablecoinImpl));
        vm.prank(admin);
        stablecoin.overrideImplementation(address(stablecoinImpl), "");
    }
}
