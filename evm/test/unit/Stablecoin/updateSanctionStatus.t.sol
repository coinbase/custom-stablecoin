// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Sanctionable} from "src/lib/Sanctionable.sol";
import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinUpdateSanctionStatusTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies updateSanctionStatus reverts for any caller without SANCTION_ROLE
    /// @dev Access control: onlyRole(SANCTION_ROLE) must reject all unauthorized callers
    function test_updateSanctionStatus_revert_unauthorized(address caller) public {
        vm.assume(caller != sanctioner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.SANCTION_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.updateSanctionStatus(alice, true);
    }

    /// @notice Verifies updateSanctionStatus reverts when attempting to sanction the zero address
    /// @dev CannotSanctionZeroAddress: minting/burning use address(0) as a sentinel; sanctioning it would break those paths
    function test_updateSanctionStatus_revert_zeroAddress() public {
        vm.expectRevert(Sanctionable.CannotSanctionZeroAddress.selector);
        vm.prank(sanctioner);
        stablecoin.updateSanctionStatus(address(0), true);
    }

    /// @notice Verifies updateSanctionStatus reverts when the account's status is already set to the requested value
    /// @dev SanctionStatusUnchanged: prevents no-op writes and misleading event emissions
    function test_updateSanctionStatus_revert_statusUnchanged(address account, bool sanctioned) public {
        vm.assume(account != address(0));
        if (sanctioned) {
            // Pre-sanction so the account is already in the `true` state
            vm.prank(sanctioner);
            stablecoin.updateSanctionStatus(account, true);
        }
        // For !sanctioned: account is already unsanctioned by default
        vm.expectRevert(abi.encodeWithSelector(Sanctionable.SanctionStatusUnchanged.selector, account, sanctioned));
        vm.prank(sanctioner);
        stablecoin.updateSanctionStatus(account, sanctioned);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies updateSanctionStatus correctly marks an address as sanctioned
    /// @dev State: isSanctioned(account) returns true after sanctioning; transfers to/from account revert
    function test_updateSanctionStatus_success_sanctions(address account) public {
        vm.assume(account != address(0));
        assertFalse(stablecoin.isSanctioned(account));
        _sanction(account);
        assertTrue(stablecoin.isSanctioned(account));
    }

    /// @notice Verifies updateSanctionStatus correctly removes a sanction from an address
    /// @dev State: isSanctioned(account) returns false after unsanctioning; transfers resume
    function test_updateSanctionStatus_success_unsanctions(address account) public {
        vm.assume(account != address(0));
        _sanction(account);
        assertTrue(stablecoin.isSanctioned(account));
        _unsanction(account);
        assertFalse(stablecoin.isSanctioned(account));
    }

    /// @notice Verifies updateSanctionStatus emits SanctionStatusUpdated with the correct account and status
    /// @dev Event integrity: account and sanctioned must match the arguments exactly
    function test_updateSanctionStatus_success_emitsEvent(address account, bool sanctioned) public {
        vm.assume(account != address(0));
        if (!sanctioned) {
            // Must pre-sanction to be able to emit an unsanction event
            vm.prank(sanctioner);
            stablecoin.updateSanctionStatus(account, true);
        }
        vm.expectEmit(true, false, false, true);
        emit Sanctionable.SanctionStatusUpdated(account, sanctioned);
        vm.prank(sanctioner);
        stablecoin.updateSanctionStatus(account, sanctioned);
    }
}
