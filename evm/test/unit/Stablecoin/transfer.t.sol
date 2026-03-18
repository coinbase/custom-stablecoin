// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Sanctionable} from "src/lib/Sanctionable.sol";
import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Tests the custom _update hook that enforces sanction and pause checks on all transfers,
/// including direct transfer() and delegated transferFrom() calls.
contract StablecoinTransferTest is StablecoinTest {
    // ── Reverts (in _update execution order: caller → from → to → pause) ─────────────────

    /// @notice Verifies transfer reverts when the caller (msg.sender) is sanctioned
    /// @dev AddressSanctioned: _requireNotSanctioned(msg.sender) is the first check in _update
    function test_transfer_revert_callerSanctioned(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _sanction(alice);
        vm.expectRevert(abi.encodeWithSelector(Sanctionable.AddressSanctioned.selector, alice));
        vm.prank(alice);
        stablecoin.transfer(bob, amount);
    }

    /// @notice Verifies transferFrom reverts when the from address is sanctioned and differs from caller
    /// @dev AddressSanctioned: _requireNotSanctioned(from) fires for the token holder; tested via transferFrom
    function test_transfer_revert_fromSanctioned(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        // carol is the caller (spender), alice is the sanctioned from address
        vm.prank(alice);
        stablecoin.approve(carol, amount);
        _sanction(alice);
        vm.expectRevert(abi.encodeWithSelector(Sanctionable.AddressSanctioned.selector, alice));
        vm.prank(carol);
        stablecoin.transferFrom(alice, carol, amount);
    }

    /// @notice Verifies transfer reverts when the recipient address is sanctioned
    /// @dev AddressSanctioned: _requireNotSanctioned(to) is the third check; catches sanctioned receivers
    function test_transfer_revert_recipientSanctioned(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _sanction(carol);
        vm.expectRevert(abi.encodeWithSelector(Sanctionable.AddressSanctioned.selector, carol));
        vm.prank(alice);
        stablecoin.transfer(carol, amount);
    }

    /// @notice Verifies transfer reverts when the contract is paused
    /// @dev EnforcedPause: fires in super._update after all three sanction checks pass
    function test_transfer_revert_whenPaused(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(alice);
        stablecoin.transfer(bob, amount);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies transfer correctly updates sender and recipient balances
    /// @dev State invariant: sender balance decreases by amount; recipient balance increases by amount
    function test_transfer_success_updatesBalances(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        uint256 aliceBalBefore = stablecoin.balanceOf(alice);
        uint256 carolBalBefore = stablecoin.balanceOf(carol);
        _transfer(alice, carol, amount);
        assertEq(stablecoin.balanceOf(alice), aliceBalBefore - amount);
        assertEq(stablecoin.balanceOf(carol), carolBalBefore + amount);
    }

    /// @notice Verifies transfer emits the ERC-20 Transfer event with correct arguments
    /// @dev Event integrity: from, to, and value must match; required by the ERC-20 standard
    function test_transfer_success_emitsTransfer(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(alice, carol, amount);
        vm.prank(alice);
        stablecoin.transfer(carol, amount);
    }
}
