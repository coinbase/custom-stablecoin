// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Blocklist} from "src/lib/Blocklist.sol";
import {Stablecoin} from "src/Stablecoin.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Tests for transferWithMemo and transferFromWithMemo.
contract StablecoinTransferWithMemoTest is StablecoinTest {
    bytes32 internal constant MEMO = keccak256("test-memo");

    // ── transferWithMemo reverts ──────────────────────────────────────────────────────────

    /// @notice Verifies transferWithMemo reverts when the sender is blocklisted
    function test_transferWithMemo_revert_fromBlocklisted(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _blocklist(alice);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, alice));
        vm.prank(alice);
        stablecoin.transferWithMemo(bob, amount, MEMO);
    }

    /// @notice Verifies transferWithMemo reverts when the recipient is blocklisted
    function test_transferWithMemo_revert_recipientBlocklisted(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _blocklist(carol);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, carol));
        vm.prank(alice);
        stablecoin.transferWithMemo(carol, amount, MEMO);
    }

    /// @notice Verifies transferWithMemo reverts when the contract is paused
    function test_transferWithMemo_revert_whenPaused(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(alice);
        stablecoin.transferWithMemo(bob, amount, MEMO);
    }

    // ── transferWithMemo happy paths ──────────────────────────────────────────────────────

    /// @notice Verifies transferWithMemo updates balances correctly
    function test_transferWithMemo_success_updatesBalances(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        uint256 aliceBalBefore = stablecoin.balanceOf(alice);
        uint256 bobBalBefore = stablecoin.balanceOf(bob);
        vm.prank(alice);
        stablecoin.transferWithMemo(bob, amount, MEMO);
        assertEq(stablecoin.balanceOf(alice), aliceBalBefore - amount);
        assertEq(stablecoin.balanceOf(bob), bobBalBefore + amount);
    }

    /// @notice Verifies transferWithMemo emits Memo with the correct value
    function test_transferWithMemo_success_emitsMemo(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.expectEmit(true, false, false, false);
        emit Stablecoin.Memo({memo: memo});
        vm.prank(alice);
        stablecoin.transferWithMemo(bob, amount, memo);
    }

    // ── transferFromWithMemo reverts ──────────────────────────────────────────────────────

    /// @notice Verifies transferFromWithMemo reverts when the caller (spender) is blocklisted
    /// @dev AddressBlocklisted: _requireNotBlocklisted(msg.sender) is the first check in _update
    function test_transferFromWithMemo_revert_callerBlocklisted(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.prank(alice);
        stablecoin.approve(carol, amount);
        _blocklist(carol);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, carol));
        vm.prank(carol);
        stablecoin.transferFromWithMemo(alice, bob, amount, MEMO);
    }

    /// @notice Verifies transferFromWithMemo reverts when the from address is blocklisted
    function test_transferFromWithMemo_revert_fromBlocklisted(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.prank(alice);
        stablecoin.approve(carol, amount);
        _blocklist(alice);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, alice));
        vm.prank(carol);
        stablecoin.transferFromWithMemo(alice, bob, amount, MEMO);
    }

    /// @notice Verifies transferFromWithMemo reverts when the recipient is blocklisted
    function test_transferFromWithMemo_revert_recipientBlocklisted(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.prank(alice);
        stablecoin.approve(carol, amount);
        _blocklist(bob);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, bob));
        vm.prank(carol);
        stablecoin.transferFromWithMemo(alice, bob, amount, MEMO);
    }

    // ── transferFromWithMemo happy paths ──────────────────────────────────────────────────

    /// @notice Verifies transferFromWithMemo updates balances and spends allowance
    function test_transferFromWithMemo_success_updatesBalances(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.prank(alice);
        stablecoin.approve(carol, amount);
        uint256 aliceBalBefore = stablecoin.balanceOf(alice);
        uint256 bobBalBefore = stablecoin.balanceOf(bob);
        vm.prank(carol);
        stablecoin.transferFromWithMemo(alice, bob, amount, MEMO);
        assertEq(stablecoin.balanceOf(alice), aliceBalBefore - amount);
        assertEq(stablecoin.balanceOf(bob), bobBalBefore + amount);
    }

    /// @notice Verifies transferFromWithMemo emits Memo with the correct value
    function test_transferFromWithMemo_success_emitsMemo(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.prank(alice);
        stablecoin.approve(carol, amount);
        vm.expectEmit(true, false, false, false);
        emit Stablecoin.Memo({memo: memo});
        vm.prank(carol);
        stablecoin.transferFromWithMemo(alice, bob, amount, memo);
    }
}
