// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Stablecoin} from "src/Stablecoin.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Tests for mintWithMemo.
contract StablecoinMintWithMemoTest is StablecoinTest {
    bytes32 internal constant MEMO = keccak256("mint-memo");

    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies mintWithMemo reverts for any caller without MINT_ROLE
    function test_mintWithMemo_revert_unauthorized(address caller) public {
        vm.assume(caller != minter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.MINT_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.mintWithMemo(alice, 1, MEMO);
    }

    /// @notice Verifies mintWithMemo reverts when the contract is paused
    function test_mintWithMemo_revert_whenPaused(uint256 amount) public {
        uint256 remaining = stablecoin.currentMintLimit(minter);
        amount = bound(amount, 1, remaining);
        _pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(minter);
        stablecoin.mintWithMemo(alice, amount, MEMO);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies mintWithMemo increases the recipient's balance
    function test_mintWithMemo_success_updatesBalance(uint256 amount) public {
        amount = bound(amount, 1, stablecoin.currentMintLimit(minter));
        uint256 balBefore = stablecoin.balanceOf(alice);
        vm.prank(minter);
        stablecoin.mintWithMemo(alice, amount, MEMO);
        assertEq(stablecoin.balanceOf(alice), balBefore + amount);
    }

    /// @notice Verifies mintWithMemo emits both Minted and Memo events
    function test_mintWithMemo_success_emitsEvents(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 1, stablecoin.currentMintLimit(minter));
        vm.expectEmit(true, true, false, true);
        emit Stablecoin.Minted({minter: minter, to: alice, amount: amount});
        vm.expectEmit(true, false, false, false);
        emit Stablecoin.Memo({memo: memo});
        vm.prank(minter);
        stablecoin.mintWithMemo(alice, amount, memo);
    }

    /// @notice Verifies mintWithMemo consumes rate limit capacity
    function test_mintWithMemo_success_consumesRateLimit(uint256 amount) public {
        uint256 limitBefore = stablecoin.currentMintLimit(minter);
        amount = bound(amount, 1, limitBefore);
        vm.prank(minter);
        stablecoin.mintWithMemo(alice, amount, MEMO);
        assertEq(stablecoin.currentMintLimit(minter), limitBefore - amount);
    }
}
