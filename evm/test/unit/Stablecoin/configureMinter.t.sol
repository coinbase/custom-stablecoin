// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {MintRateLimit} from "src/lib/MintRateLimit.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinConfigureMinterTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies configureMinter reverts for any caller without MINT_RATE_LIMIT_ROLE
    /// @dev Access control: onlyRole(MINT_RATE_LIMIT_ROLE) must reject all unauthorized callers
    function test_configureMinter_revert_unauthorized(address caller) public {
        vm.assume(caller != rateLimitAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.MINT_RATE_LIMIT_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.configureMinter(minter, 1, 1);
    }

    /// @notice Verifies configureMinter reverts when the target address does not hold MINT_ROLE
    /// @dev _checkRole(MINT_ROLE, minter): configureMinter cannot configure non-minters
    function test_configureMinter_revert_notMintRole(address target) public {
        vm.assume(!stablecoin.hasRole(stablecoin.MINT_ROLE(), target));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, target, stablecoin.MINT_ROLE()
            )
        );
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(target, 1, 1);
    }

    /// @notice Verifies configureMinter reverts when limit is zero
    /// @dev InvalidMinterConfig: both limit and interval must be non-zero for a valid config
    function test_configureMinter_revert_zeroLimit(address target, uint40 interval) public {
        vm.assume(target != minter && target != address(0));
        vm.assume(interval != 0);
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), target);
        vm.stopPrank();
        vm.expectRevert(MintRateLimit.InvalidMinterConfig.selector);
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(target, 0, interval);
    }

    /// @notice Verifies configureMinter reverts when interval is zero
    /// @dev InvalidMinterConfig: both limit and interval must be non-zero for a valid config
    function test_configureMinter_revert_zeroInterval(address target, uint256 limit) public {
        vm.assume(target != minter && target != address(0));
        limit = bound(limit, 1, type(uint128).max);
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), target);
        vm.stopPrank();
        vm.expectRevert(MintRateLimit.InvalidMinterConfig.selector);
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(target, limit, 0);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies configureMinter stores the new limit and interval for the minter
    /// @dev State: currentMintLimit(minter) equals the new limit immediately after configuration
    function test_configureMinter_success_updatesConfig(uint256 limit, uint40 interval) public {
        limit = bound(limit, 1, type(uint128).max);
        vm.assume(interval != 0);
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter, limit, interval);
        assertEq(stablecoin.currentMintLimit(minter), limit);
    }

    /// @notice Verifies configureMinter emits MinterConfigured with the correct minter, limit, and interval
    /// @dev Event integrity: all three fields must match the arguments passed to configureMinter
    function test_configureMinter_success_emitsMinterConfigured(uint256 limit, uint40 interval) public {
        limit = bound(limit, 1, type(uint128).max);
        vm.assume(interval != 0);
        vm.expectEmit(true, false, false, true);
        emit MintRateLimit.MinterConfigured({minter: minter, limit: limit, interval: interval});
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter, limit, interval);
    }
}
