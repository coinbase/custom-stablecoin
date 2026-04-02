// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {Stablecoin} from "src/Stablecoin.sol";
import {TwoStepUpgradeableBeacon} from "src/TwoStepUpgradeableBeacon.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract TwoStepUpgradeableBeaconTest is StablecoinTest {
    TwoStepUpgradeableBeacon internal twoStepBeacon;

    function setUp() public override {
        super.setUp();
        twoStepBeacon = new TwoStepUpgradeableBeacon(address(stablecoinImpl), admin);
    }

    // ── Constructor ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies the beacon stores the initial implementation on deployment
    /// @dev State: implementation() must equal the address passed to the constructor
    function test_constructor_success_setsImplementation() public view {
        assertEq(twoStepBeacon.implementation(), address(stablecoinImpl));
    }

    /// @notice Verifies the beacon sets the initial owner on deployment
    /// @dev State: owner() must equal the address passed to the constructor
    function test_constructor_success_setsOwner() public view {
        assertEq(twoStepBeacon.owner(), admin);
    }

    /// @notice Verifies the constructor reverts when the implementation has no code
    /// @dev BeaconInvalidImplementation: EOA or empty address must be rejected
    function test_constructor_revert_invalidImplementation(address impl) public {
        vm.assume(impl.code.length == 0);
        vm.expectRevert(abi.encodeWithSelector(UpgradeableBeacon.BeaconInvalidImplementation.selector, impl));
        new TwoStepUpgradeableBeacon(impl, admin);
    }

    // ── upgradeTo ─────────────────────────────────────────────────────────────────────────

    /// @notice Verifies upgradeTo updates the implementation address
    /// @dev State: implementation() must equal newImplementation after the call
    function test_upgradeTo_success_updatesImplementation() public {
        Stablecoin newImpl = new Stablecoin();
        vm.prank(admin);
        twoStepBeacon.upgradeTo(address(newImpl));
        assertEq(twoStepBeacon.implementation(), address(newImpl));
    }

    /// @notice Verifies upgradeTo emits Upgraded with the new implementation address
    /// @dev Event integrity: Upgraded must fire so off-chain indexers track upgrades
    function test_upgradeTo_success_emitsUpgraded() public {
        Stablecoin newImpl = new Stablecoin();
        vm.expectEmit(true, false, false, false);
        emit UpgradeableBeacon.Upgraded(address(newImpl));
        vm.prank(admin);
        twoStepBeacon.upgradeTo(address(newImpl));
    }

    /// @notice Verifies upgradeTo reverts for any caller who is not the owner
    /// @dev Access control: onlyOwner must reject all non-owner callers
    function test_upgradeTo_revert_unauthorized(address caller) public {
        vm.assume(caller != admin);
        Stablecoin newImpl = new Stablecoin();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        twoStepBeacon.upgradeTo(address(newImpl));
    }

    /// @notice Verifies upgradeTo reverts when the new implementation has no code
    /// @dev BeaconInvalidImplementation: EOA or empty address must be rejected before the storage write
    function test_upgradeTo_revert_invalidImplementation(address impl) public {
        vm.assume(impl.code.length == 0);
        vm.expectRevert(abi.encodeWithSelector(UpgradeableBeacon.BeaconInvalidImplementation.selector, impl));
        vm.prank(admin);
        twoStepBeacon.upgradeTo(impl);
    }

    // ── Two-step ownership ────────────────────────────────────────────────────────────────

    /// @notice Verifies ownership transfer requires acceptance from the new owner
    /// @dev Two-step: owner() must not change until the pending owner calls acceptOwnership
    function test_transferOwnership_success_requiresAcceptance(address newOwner) public {
        vm.assume(newOwner != address(0) && newOwner != admin);
        vm.prank(admin);
        twoStepBeacon.transferOwnership(newOwner);

        assertEq(twoStepBeacon.owner(), admin);
        assertEq(twoStepBeacon.pendingOwner(), newOwner);

        vm.prank(newOwner);
        twoStepBeacon.acceptOwnership();
        assertEq(twoStepBeacon.owner(), newOwner);
    }

    /// @notice Verifies a pending transfer can be cancelled by proposing a different address
    /// @dev Cancellation: re-calling transferOwnership overwrites the pending owner
    function test_transferOwnership_success_canBeCancelled(address wrongOwner, address correctOwner) public {
        vm.assume(wrongOwner != address(0) && wrongOwner != admin);
        vm.assume(correctOwner != address(0) && correctOwner != admin && correctOwner != wrongOwner);

        vm.startPrank(admin);
        twoStepBeacon.transferOwnership(wrongOwner);
        twoStepBeacon.transferOwnership(correctOwner);
        vm.stopPrank();

        assertEq(twoStepBeacon.pendingOwner(), correctOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, wrongOwner));
        vm.prank(wrongOwner);
        twoStepBeacon.acceptOwnership();
    }

    /// @notice Verifies non-pending owner cannot accept ownership
    /// @dev Security: only the exact pending owner address may call acceptOwnership
    function test_transferOwnership_revert_nonPendingOwnerCannotAccept(address pendingOwner, address impostor) public {
        vm.assume(pendingOwner != address(0) && pendingOwner != admin);
        vm.assume(impostor != pendingOwner);

        vm.prank(admin);
        twoStepBeacon.transferOwnership(pendingOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, impostor));
        vm.prank(impostor);
        twoStepBeacon.acceptOwnership();
    }

    // ── renounceOwnership ─────────────────────────────────────────────────────────────────

    /// @notice Verifies renounceOwnership always reverts, even when called by the owner
    function test_renounceOwnership_revert_disabled() public {
        vm.expectRevert(TwoStepUpgradeableBeacon.RenouneOwnershipDisabled.selector);
        vm.prank(admin);
        twoStepBeacon.renounceOwnership();
    }

    /// @notice Verifies renounceOwnership reverts with OwnableUnauthorizedAccount for non-owners
    function test_renounceOwnership_revert_unauthorized(address caller) public {
        vm.assume(caller != admin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        twoStepBeacon.renounceOwnership();
    }
}
