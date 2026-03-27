// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import {Stablecoin} from "src/Stablecoin.sol";
import {TwoStepUpgradeableBeacon} from "src/TwoStepUpgradeableBeacon.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";
import {StablecoinV2} from "test/lib/mocks/StablecoinV2.sol";

contract StablecoinupgradeBeaconToAndCallTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies upgradeBeaconToAndCall reverts for any caller without DEFAULT_ADMIN_ROLE
    /// @dev Access control: onlyRole(DEFAULT_ADMIN_ROLE) must reject all unauthorized callers
    function test_upgradeBeaconToAndCall_revert_unauthorized(address caller) public {
        vm.assume(!stablecoin.hasRole(stablecoin.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.upgradeBeaconToAndCall(address(beacon), "");
    }

    /// @notice Verifies upgradeBeaconToAndCall reverts when newBeacon is the zero address
    /// @dev InvalidBeacon: zero address has no code; must be rejected before the slot write
    function test_upgradeBeaconToAndCall_revert_invalidBeacon_zero() public {
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidBeacon.selector, address(0)));
        vm.prank(admin);
        stablecoin.upgradeBeaconToAndCall(address(0), "");
    }

    /// @notice Verifies upgradeBeaconToAndCall reverts when newBeacon points to an address with no code
    /// @dev InvalidBeacon: code.length == 0 check prevents pointing at EOAs or empty addresses
    function test_upgradeBeaconToAndCall_revert_invalidBeacon_noCode(address newBeacon) public {
        vm.assume(newBeacon != address(0));
        vm.assume(newBeacon.code.length == 0);
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidBeacon.selector, newBeacon));
        vm.prank(admin);
        stablecoin.upgradeBeaconToAndCall(newBeacon, "");
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies upgradeBeaconToAndCall writes the beacon slot so the proxy follows the new beacon
    /// @dev After the call, the proxy delegates to the new beacon's implementation, not the old one
    function test_upgradeBeaconToAndCall_success_updatesBeaconSlot() public {
        Stablecoin newImpl = new Stablecoin();
        TwoStepUpgradeableBeacon newBeacon = new TwoStepUpgradeableBeacon(address(newImpl), admin);

        vm.prank(admin);
        stablecoin.upgradeBeaconToAndCall(address(newBeacon), "");

        // The ERC-1967 beacon slot should now point at newBeacon
        bytes32 slotValue = vm.load(address(proxy), ERC1967Utils.BEACON_SLOT);
        address resolvedBeacon = address(uint160(uint256(slotValue)));
        assertEq(resolvedBeacon, address(newBeacon));

        // The beacon resolves to the expected implementation address
        assertEq(IBeacon(resolvedBeacon).implementation(), address(newImpl));

        // Proxy still functions correctly via the new beacon
        assertEq(stablecoin.name(), TOKEN_NAME);
    }

    /// @notice Verifies upgradeBeaconToAndCall emits the BeaconUpgraded event with the new beacon address
    /// @dev Event integrity: IERC1967.BeaconUpgraded must be emitted so indexers track the beacon swap
    function test_upgradeBeaconToAndCall_success_emitsBeaconUpgraded() public {
        Stablecoin newImpl = new Stablecoin();
        TwoStepUpgradeableBeacon newBeacon = new TwoStepUpgradeableBeacon(address(newImpl), admin);

        vm.expectEmit(true, false, false, false);
        emit IERC1967.BeaconUpgraded(address(newBeacon));
        vm.prank(admin);
        stablecoin.upgradeBeaconToAndCall(address(newBeacon), "");
    }

    /// @notice Verifies the proxy reports the new VERSION after upgrading the beacon to a new implementation
    /// @dev Version check: delegatecall routes to the new impl; VERSION() must reflect the new deployment
    function test_upgradeBeaconToAndCall_success_updatesVersion() public {
        string memory v1 = stablecoin.VERSION();

        StablecoinV2 newImpl = new StablecoinV2();
        TwoStepUpgradeableBeacon newBeacon = new TwoStepUpgradeableBeacon(address(newImpl), admin);
        vm.prank(admin);
        stablecoin.upgradeBeaconToAndCall(address(newBeacon), "");

        assertNotEq(stablecoin.VERSION(), v1);
        assertEq(stablecoin.VERSION(), newImpl.VERSION());
    }

    /// @notice Verifies the proxy can be rolled back to the original beacon after an upgrade
    /// @dev Rollback: beacon slot is mutable in both directions; original beacon must be restorable
    function test_upgradeBeaconToAndCall_success_beaconSlotRevertsOnRollback() public {
        Stablecoin newImpl = new Stablecoin();
        TwoStepUpgradeableBeacon newBeacon = new TwoStepUpgradeableBeacon(address(newImpl), admin);

        // Upgrade to a new beacon
        vm.prank(admin);
        stablecoin.upgradeBeaconToAndCall(address(newBeacon), "");
        assertEq(address(uint160(uint256(vm.load(address(proxy), ERC1967Utils.BEACON_SLOT)))), address(newBeacon));

        // Roll back to the original beacon
        vm.prank(admin);
        stablecoin.upgradeBeaconToAndCall(address(beacon), "");
        assertEq(address(uint160(uint256(vm.load(address(proxy), ERC1967Utils.BEACON_SLOT)))), address(beacon));

        // Proxy still functions correctly
        assertEq(stablecoin.name(), TOKEN_NAME);
    }
}
