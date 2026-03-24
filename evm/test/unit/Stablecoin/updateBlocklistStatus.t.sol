// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Blocklist} from "src/lib/Blocklist.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinUpdateBlocklistStatusTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies updateBlocklistStatus reverts for any caller without BLOCKLIST_ROLE
    /// @dev Access control: onlyRole(BLOCKLIST_ROLE) must reject all unauthorized callers
    function test_updateBlocklistStatus_revert_unauthorized(address caller) public {
        vm.assume(caller != blocklister);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.BLOCKLIST_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.updateBlocklistStatus(alice, true);
    }

    /// @notice Verifies updateBlocklistStatus reverts when attempting to blocklist the zero address
    /// @dev CannotBlocklistZeroAddress: minting/burning use address(0) as a sentinel; blocklisting it would break those paths
    function test_updateBlocklistStatus_revert_zeroAddress() public {
        vm.expectRevert(Blocklist.CannotBlocklistZeroAddress.selector);
        vm.prank(blocklister);
        stablecoin.updateBlocklistStatus(address(0), true);
    }

    /// @notice Verifies updateBlocklistStatus reverts when the account's status is already set to the requested value
    /// @dev BlocklistStatusUnchanged: prevents no-op writes and misleading event emissions
    function test_updateBlocklistStatus_revert_statusUnchanged(address account, bool blocklisted) public {
        vm.assume(account != address(0));
        if (blocklisted) {
            vm.prank(blocklister);
            stablecoin.updateBlocklistStatus(account, true);
        }
        vm.expectRevert(abi.encodeWithSelector(Blocklist.BlocklistStatusUnchanged.selector, account, blocklisted));
        vm.prank(blocklister);
        stablecoin.updateBlocklistStatus(account, blocklisted);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies updateBlocklistStatus correctly marks an address as blocklisted
    /// @dev State: isBlocklisted(account) returns true after blocklisting; transfers to/from account revert
    function test_updateBlocklistStatus_success_blocklists(address account) public {
        vm.assume(account != address(0));
        assertFalse(stablecoin.isBlocklisted(account));
        _blocklist(account);
        assertTrue(stablecoin.isBlocklisted(account));
    }

    /// @notice Verifies updateBlocklistStatus correctly removes an address from the blocklist
    /// @dev State: isBlocklisted(account) returns false after unblocklisting; transfers resume
    function test_updateBlocklistStatus_success_unblocklists(address account) public {
        vm.assume(account != address(0));
        _blocklist(account);
        assertTrue(stablecoin.isBlocklisted(account));
        _unblocklist(account);
        assertFalse(stablecoin.isBlocklisted(account));
    }

    /// @notice Verifies updateBlocklistStatus emits BlocklistStatusUpdated with the correct account and status
    /// @dev Event integrity: account and blocklisted must match the arguments exactly
    function test_updateBlocklistStatus_success_emitsEvent(address account, bool blocklisted) public {
        vm.assume(account != address(0));
        if (!blocklisted) {
            vm.prank(blocklister);
            stablecoin.updateBlocklistStatus(account, true);
        }
        vm.expectEmit(true, false, false, true);
        emit Blocklist.BlocklistStatusUpdated({account: account, blocklisted: blocklisted});
        vm.prank(blocklister);
        stablecoin.updateBlocklistStatus(account, blocklisted);
    }
}
