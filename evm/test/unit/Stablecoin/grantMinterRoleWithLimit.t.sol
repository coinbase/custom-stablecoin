// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {MintRateLimit} from "src/lib/MintRateLimit.sol";
import {Stablecoin} from "src/Stablecoin.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinGrantMinterRoleWithLimitTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies grantMinterRoleWithLimit reverts for any caller without DEFAULT_ADMIN_ROLE
    /// @dev Access control: onlyRole(DEFAULT_ADMIN_ROLE) must reject all unauthorized callers
    function test_grantMinterRoleWithLimit_revert_unauthorized(address caller) public {
        vm.assume(caller != admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.grantMinterRoleWithLimit(makeAddr("newMinter"), 1, 1);
    }

    /// @notice Verifies grantMinterRoleWithLimit reverts when limit is zero
    /// @dev InvalidMinterConfig: limit must be non-zero for a valid rate-limit configuration
    function test_grantMinterRoleWithLimit_revert_zeroLimit(address target, uint40 interval) public {
        vm.assume(target != address(0));
        vm.assume(interval != 0);
        vm.expectRevert(MintRateLimit.InvalidMinterConfig.selector);
        vm.prank(admin);
        stablecoin.grantMinterRoleWithLimit(target, 0, interval);
    }

    /// @notice Verifies grantMinterRoleWithLimit reverts when interval is zero
    /// @dev InvalidMinterConfig: interval must be non-zero for a valid rate-limit configuration
    function test_grantMinterRoleWithLimit_revert_zeroInterval(address target, uint256 limit) public {
        vm.assume(target != address(0));
        limit = bound(limit, 1, type(uint128).max);
        vm.expectRevert(MintRateLimit.InvalidMinterConfig.selector);
        vm.prank(admin);
        stablecoin.grantMinterRoleWithLimit(target, limit, 0);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies grantMinterRoleWithLimit grants MINT_ROLE to the target address
    /// @dev Role grant: hasRole(MINT_ROLE, minter) must be true after the call
    function test_grantMinterRoleWithLimit_success_grantsRole(address target, uint256 limit, uint40 interval) public {
        vm.assume(target != address(0));
        limit = bound(limit, 1, type(uint128).max);
        vm.assume(interval != 0);
        vm.prank(admin);
        stablecoin.grantMinterRoleWithLimit(target, limit, interval);
        assertTrue(stablecoin.hasRole(stablecoin.MINT_ROLE(), target));
    }

    /// @notice Verifies grantMinterRoleWithLimit sets the rate-limit so currentMintLimit equals limit
    /// @dev Config: currentMintLimit(minter) must equal the configured limit immediately after the call
    function test_grantMinterRoleWithLimit_success_configuresMintLimit(address target, uint256 limit, uint40 interval)
        public
    {
        vm.assume(target != address(0));
        limit = bound(limit, 1, type(uint128).max);
        vm.assume(interval != 0);
        vm.prank(admin);
        stablecoin.grantMinterRoleWithLimit(target, limit, interval);
        assertEq(stablecoin.currentMintLimit(target), limit);
    }

    /// @notice Verifies the minter can mint immediately after grantMinterRoleWithLimit without a separate configure step
    /// @dev Atomicity: the minter must not revert with MinterNotConfigured on the first mint call
    function test_grantMinterRoleWithLimit_success_canMintImmediately(uint256 limit, uint40 interval) public {
        limit = bound(limit, 1, type(uint128).max);
        vm.assume(interval != 0);
        address newMinter = makeAddr("newMinter");
        vm.prank(admin);
        stablecoin.grantMinterRoleWithLimit(newMinter, limit, interval);
        vm.prank(newMinter);
        stablecoin.mint(alice, 1);
        assertEq(stablecoin.balanceOf(alice), INITIAL_MINT + 1);
    }

    /// @notice Verifies grantMinterRoleWithLimit emits both RoleGranted and MinterConfigured
    /// @dev Event integrity: both events must fire with the correct arguments in a single call
    function test_grantMinterRoleWithLimit_success_emitsEvents(address target, uint256 limit, uint40 interval) public {
        vm.assume(target != address(0));
        vm.assume(!stablecoin.hasRole(stablecoin.MINT_ROLE(), target));
        limit = bound(limit, 1, type(uint128).max);
        vm.assume(interval != 0);
        vm.expectEmit(true, true, true, true);
        emit IAccessControl.RoleGranted(stablecoin.MINT_ROLE(), target, admin);
        vm.expectEmit(true, false, false, true);
        emit MintRateLimit.MinterConfigured({minter: target, limit: limit, interval: interval});
        vm.prank(admin);
        stablecoin.grantMinterRoleWithLimit(target, limit, interval);
    }

    /// @notice Verifies grantMinterRoleWithLimit is idempotent for the role grant when called twice
    /// @dev Role idempotency: granting an already-held role updates the config without error
    function test_grantMinterRoleWithLimit_success_idempotentRoleGrant(
        uint256 limit1,
        uint40 interval1,
        uint256 limit2,
        uint40 interval2
    ) public {
        limit1 = bound(limit1, 1, type(uint128).max);
        limit2 = bound(limit2, 1, type(uint128).max);
        vm.assume(interval1 != 0);
        vm.assume(interval2 != 0);
        address newMinter = makeAddr("newMinter");
        vm.startPrank(admin);
        stablecoin.grantMinterRoleWithLimit(newMinter, limit1, interval1);
        stablecoin.grantMinterRoleWithLimit(newMinter, limit2, interval2);
        vm.stopPrank();
        assertTrue(stablecoin.hasRole(stablecoin.MINT_ROLE(), newMinter));
        assertEq(stablecoin.currentMintLimit(newMinter), limit2);
    }
}
