// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinPauseTest is StablecoinTest {
    event Paused(address account);

    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies pause reverts for any caller without PAUSE_ROLE
    /// @dev Access control: onlyRole(PAUSE_ROLE) must reject all unauthorized callers
    function test_pause_revert_unauthorized(address caller) public {
        vm.assume(caller != pauser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.PAUSE_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.pause();
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies pause sets paused() to true and blocks all subsequent transfers
    /// @dev State: paused() must return true; any transfer attempt must revert with EnforcedPause
    function test_pause_success_pausesTransfers(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _pause();
        assertTrue(stablecoin.paused());
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(alice);
        stablecoin.transfer(bob, amount);
    }

    /// @notice Verifies pause emits the Paused event with the pauser's address
    /// @dev Event integrity: standard OZ Pausable event must be emitted with msg.sender
    function test_pause_success_emitsPaused() public {
        vm.expectEmit(false, false, false, true);
        emit Paused(pauser);
        vm.prank(pauser);
        stablecoin.pause();
    }
}
