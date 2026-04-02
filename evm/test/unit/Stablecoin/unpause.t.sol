// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinUnpauseTest is StablecoinTest {
    event Unpaused(address account);

    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies unpause reverts for any caller without UNPAUSE_ROLE
    /// @dev Access control: onlyRole(UNPAUSE_ROLE) must reject all unauthorized callers
    function test_unpause_revert_unauthorized(address caller) public {
        vm.assume(caller != pauser);
        _pause();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.UNPAUSE_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.unpause();
    }

    /// @notice Verifies unpause reverts when the contract is not currently paused
    /// @dev ExpectedPause: OZ Pausable requires the contract to be paused before unpausing
    function test_unpause_revert_notPaused() public {
        assertFalse(stablecoin.paused());
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ExpectedPause()"))));
        vm.prank(pauser);
        stablecoin.unpause();
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies unpause sets paused() to false and re-enables transfers
    /// @dev State: paused() must return false after unpausing; transfers must succeed again
    function test_unpause_success_resumesTransfers(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _pause();
        _unpause();
        assertFalse(stablecoin.paused());
        uint256 aliceBalBefore = stablecoin.balanceOf(alice);
        _transfer(alice, bob, amount);
        assertEq(stablecoin.balanceOf(alice), aliceBalBefore - amount);
    }

    /// @notice Verifies unpause emits the Unpaused event with the caller's address
    /// @dev Event integrity: standard OZ Pausable event must be emitted with msg.sender
    function test_unpause_success_emitsUnpaused() public {
        _pause();
        vm.expectEmit(false, false, false, true);
        emit Unpaused(pauser);
        vm.prank(pauser);
        stablecoin.unpause();
    }
}
