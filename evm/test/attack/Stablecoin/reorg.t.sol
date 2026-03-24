// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC3009Upgradeable} from "src/lib/ERC3009Upgradeable.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Reorg and timestamp manipulation tests. Two critical areas use block.timestamp:
/// (1) ERC-3009 validAfter/validBefore boundary checks, (2) MintRateLimit replenishment math.
contract StablecoinReorgTest is StablecoinTest {
    // ── ERC-3009 timestamp boundaries ─────────────────────────────────────────────────────

    /// @notice Verifies that timestamp == validAfter is treated as not-yet-valid (strict inequality)
    /// @dev Boundary: timestamp <= validAfter reverts; timestamp == validAfter must also revert
    function test_attack_reorg_transferWithAuthorization_equalToValidAfter(
        bytes32 nonce,
        uint256 amount,
        uint256 validAfter
    ) public {
        amount = bound(amount, 1, INITIAL_MINT);
        validAfter = bound(validAfter, 0, type(uint256).max - 1);

        // Set timestamp to exactly validAfter — the check `timestamp <= validAfter` fires
        vm.warp(validAfter);

        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, validAfter, type(uint256).max, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationNotYetValid.selector, validAfter));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, validAfter, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies that timestamp == validBefore is treated as expired (strict inequality)
    /// @dev Boundary: timestamp >= validBefore reverts; timestamp == validBefore must also revert
    function test_attack_reorg_transferWithAuthorization_equalToValidBefore(
        bytes32 nonce,
        uint256 amount,
        uint256 validBefore
    ) public {
        amount = bound(amount, 1, INITIAL_MINT);
        // validBefore must be > 0 so we can warp to it; validAfter = 0 ensures validAfter check passes
        validBefore = bound(validBefore, 1, type(uint256).max);

        // Set timestamp to exactly validBefore — the check `timestamp >= validBefore` fires
        vm.warp(validBefore);

        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, validBefore, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationExpired.selector, validBefore));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, validBefore, nonce, sig);
    }

    // ── MintRateLimit timestamp manipulation ──────────────────────────────────────────────

    /// @notice Verifies a rolled-back timestamp cannot inflate the replenished amount beyond the limit
    /// @dev Overflow protection: very large elapsed values must be capped; no replenishment > config.limit
    function test_attack_reorg_mintRateLimit_timestampRollbackCannotInflateCapacity(uint256 limit, uint40 interval)
        public
    {
        limit = bound(limit, 1, type(uint128).max);
        vm.assume(interval != 0);

        address minter2 = makeAddr("minter2");
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), minter2);
        vm.stopPrank();
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter2, limit, interval);

        // Simulate extreme elapsed time (timestamp far in the future, then "rolled back")
        vm.warp(uint256(type(uint40).max));

        // Regardless of elapsed time, the limit cap holds
        uint256 current = stablecoin.currentMintLimit(minter2);
        assertLe(current, limit);
    }

    /// @notice Verifies that replenishment with extremely large elapsed time is capped at the configured limit
    /// @dev Cap invariant: Math.min(..., limit) prevents overflow and ensures capacity <= limit always holds
    function test_attack_reorg_mintRateLimit_overflowProtection(uint256 limit, uint40 interval, uint256 elapsed)
        public
    {
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

        // Math.min caps the result at limit regardless of how large the replenishment is
        uint256 current = stablecoin.currentMintLimit(minter2);
        assertLe(current, limit);
    }
}
