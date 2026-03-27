// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Regression tests for the mint rate-limit timing invariant. Replenishment is always
/// anchored to the most recent consumption via `lastConsumption`, ensuring that no combination
/// of partial mints and timing can grant more capacity than the configured limit allows within
/// a single interval.
contract StablecoinDoubleMintTest is StablecoinTest {
    uint216 internal constant LIMIT = 100e6;
    uint40 internal constant INTERVAL = 1 days;

    address internal minter2;

    function setUp() public override {
        super.setUp();

        minter2 = makeAddr("minter2");
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), minter2);
        vm.stopPrank();
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter2, LIMIT, INTERVAL);
    }

    /// @notice A minter who waits a full interval before their first mint should not
    ///         regain the full limit in less than one interval afterward.
    function test_attack_doubleMint_waitThenMintDoesNotGrantPrematureReplenishment() public {
        // Day 0 → Day 1: minter waits a full interval, then mints the full limit.
        vm.warp(block.timestamp + INTERVAL);
        vm.prank(minter2);
        stablecoin.mint(alice, LIMIT);

        // Half an interval later the minter should have at most half the limit.
        vm.warp(block.timestamp + INTERVAL / 2);
        uint256 available = stablecoin.currentMintLimit(minter2);
        assertLe(available, LIMIT / 2, "premature replenishment: available exceeds half the limit");
    }

    /// @notice Minting 0 should not allow the minter to "bank" remaining for a later
    ///         double-sized mint.
    function test_attack_doubleMint_mintZeroDoesNotBankRemaining() public {
        // Day 1: mint 0 — no capacity consumed, but remaining should not grow beyond limit.
        vm.warp(block.timestamp + INTERVAL);
        vm.prank(minter2);
        stablecoin.mint(alice, 0);

        // Immediately mint the full limit (this should succeed — remaining was already limit).
        vm.prank(minter2);
        stablecoin.mint(alice, LIMIT);

        // Half an interval later, capacity should be at most half the limit.
        vm.warp(block.timestamp + INTERVAL / 2);
        uint256 available = stablecoin.currentMintLimit(minter2);
        assertLe(available, LIMIT / 2, "banking via mint-zero: available exceeds half the limit");
    }

    /// @notice After consuming the full limit, exactly one interval must pass before
    ///         the full limit is available again.
    function test_attack_doubleMint_fullReplenishmentRequiresFullInterval() public {
        // Consume the full limit immediately.
        vm.prank(minter2);
        stablecoin.mint(alice, LIMIT);

        // Warp to exactly one interval later — full limit should be restored.
        vm.warp(block.timestamp + INTERVAL);
        assertEq(stablecoin.currentMintLimit(minter2), LIMIT, "full interval should restore full limit");
    }

    /// @notice Alternating full-mint / skip cycles should never yield more than the
    ///         limit in a single mint.
    function test_attack_doubleMint_alternatingCyclesRespectLimit() public {
        // Use a fixed base time and reconfigure to avoid Solidity CSE of block.timestamp
        // across vm.warp boundaries within the same function.
        uint256 base = 100_000;
        vm.warp(base);
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter2, LIMIT, INTERVAL);

        // Cycle 1: wait a full interval, then mint.
        vm.warp(base + INTERVAL);
        vm.prank(minter2);
        stablecoin.mint(alice, LIMIT);

        // Cycle 2: wait another full interval, mint again — should still be capped at limit.
        vm.warp(base + 2 * INTERVAL);
        uint256 available = stablecoin.currentMintLimit(minter2);
        assertEq(available, LIMIT, "after full interval available should equal limit");

        vm.prank(minter2);
        stablecoin.mint(alice, LIMIT);

        // Half interval later: at most half.
        vm.warp(base + 2 * INTERVAL + INTERVAL / 2);
        available = stablecoin.currentMintLimit(minter2);
        assertLe(available, LIMIT / 2, "premature replenishment after alternating cycles");
    }

    /// @notice Fuzz: after depleting to 0, the available capacity after any sub-interval
    ///         wait must be proportional and never exceed the limit.
    function test_attack_doubleMint_fuzz_replenishmentProportional(uint256 waitBefore, uint256 waitAfter) public {
        waitBefore = bound(waitBefore, 0, 10 * INTERVAL);
        waitAfter = bound(waitAfter, 0, 10 * INTERVAL);

        // Wait, then mint the full available capacity.
        vm.warp(block.timestamp + waitBefore);
        uint256 available = stablecoin.currentMintLimit(minter2);
        vm.prank(minter2);
        stablecoin.mint(alice, available);

        // Wait again, check replenishment is bounded.
        vm.warp(block.timestamp + waitAfter);
        uint256 replenished = stablecoin.currentMintLimit(minter2);
        assertLe(replenished, LIMIT, "replenished capacity must never exceed limit");

        // If the wait is less than a full interval, capacity must be strictly less than limit.
        if (waitAfter < INTERVAL && available > 0) {
            assertLt(replenished, LIMIT, "sub-interval wait should not fully restore limit");
        }
    }
}
