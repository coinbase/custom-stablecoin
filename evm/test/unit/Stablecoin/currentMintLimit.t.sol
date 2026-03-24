// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinCurrentMintLimitTest is StablecoinTest {
    // ── Happy paths (no reverts — this is a pure view) ────────────────────────────────────

    /// @notice Verifies currentMintLimit panics with division-by-zero for an unconfigured address
    /// @dev Edge case: unconfigured minter has interval=0; Math.mulDiv(elapsed, 0, 0) triggers Panic(0x12)
    function test_currentMintLimit_revert_divisionByZero_whenNotConfigured(address target) public {
        vm.assume(target != minter);
        // Unregistered minter has interval=0; Math.mulDiv(elapsed, 0, 0) = 0/0 → Panic(divisionByZero)
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x4e487b71), uint256(18)));
        stablecoin.currentMintLimit(target);
    }

    /// @notice Verifies currentMintLimit returns the full configured limit immediately after configuration
    /// @dev State: remaining == limit at configuration time; no elapsed time means no additional replenishment
    function test_currentMintLimit_success_returnsFullLimitAtStart(uint256 limit) public {
        limit = bound(limit, 1, type(uint128).max);
        address minter2 = makeAddr("minter2");
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), minter2);
        vm.stopPrank();
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter2, limit, 1 days);
        assertEq(stablecoin.currentMintLimit(minter2), limit);
    }

    /// @notice Verifies currentMintLimit reflects linear replenishment proportional to elapsed time
    /// @dev Replenishment: amount = Math.mulDiv(elapsed, limit, interval); partial interval yields partial refill
    function test_currentMintLimit_success_replenishesOverTime(uint256 limit, uint40 interval, uint256 elapsed) public {
        limit = bound(limit, 1e6, 1e18);
        vm.assume(interval != 0);
        elapsed = bound(elapsed, 1, uint256(type(uint40).max));

        address minter2 = makeAddr("minter2");
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), minter2);
        vm.stopPrank();
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter2, limit, interval);

        // Consume half the capacity
        uint256 mintAmount = limit / 2;
        if (mintAmount > 0) {
            vm.prank(minter2);
            stablecoin.mint(carol, mintAmount);
        }
        uint256 remainingAfterMint = stablecoin.currentMintLimit(minter2);

        vm.warp(block.timestamp + elapsed);

        uint256 current = stablecoin.currentMintLimit(minter2);

        // Invariant: capped at limit
        assertLe(current, limit);
        // Invariant: only replenishes (never decreases below remaining)
        assertGe(current, remainingAfterMint);
        // Invariant: if elapsed >= interval the limit is fully restored
        if (elapsed >= interval) {
            assertEq(current, limit);
        }
    }

    /// @notice Verifies currentMintLimit never exceeds the configured limit regardless of elapsed time
    /// @dev Cap invariant: Math.min(remaining + replenishment, limit) must always hold
    function test_currentMintLimit_success_capsAtLimit(uint256 limit, uint40 interval, uint256 elapsed) public {
        limit = bound(limit, 1, type(uint128).max);
        vm.assume(interval != 0);
        elapsed = bound(elapsed, 0, uint256(type(uint40).max));

        address minter2 = makeAddr("minter2");
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), minter2);
        vm.stopPrank();
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter2, limit, interval);

        vm.warp(block.timestamp + elapsed);
        assertLe(stablecoin.currentMintLimit(minter2), limit);
    }

    /// @notice Verifies currentMintLimit decreases by exactly the minted amount after a mint
    /// @dev State: remaining capacity must reflect the consumed amount; replenishment is unchanged
    function test_currentMintLimit_success_decreasesAfterMint(uint256 amount) public {
        uint256 limitBefore = stablecoin.currentMintLimit(minter);
        amount = bound(amount, 1, limitBefore);
        _mint(alice, amount);
        assertEq(stablecoin.currentMintLimit(minter), limitBefore - amount);
    }
}
