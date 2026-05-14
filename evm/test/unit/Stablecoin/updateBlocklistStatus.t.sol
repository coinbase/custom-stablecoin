// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Blocklist} from "src/lib/Blocklist.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinBlocklistTest is StablecoinTest {
    // ── blocklist() reverts ──────────────────────────────────────────────────────────────

    /// @notice Verifies blocklist reverts for any caller without BLOCKLIST_ROLE
    function test_blocklist_revert_unauthorized(address caller) public {
        vm.assume(caller != blocklister);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.BLOCKLIST_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.blocklist(alice);
    }

    /// @notice Verifies blocklist reverts when attempting to blocklist the zero address
    function test_blocklist_revert_zeroAddress() public {
        vm.expectRevert(Blocklist.CannotBlocklistZeroAddress.selector);
        vm.prank(blocklister);
        stablecoin.blocklist(address(0));
    }

    /// @notice Verifies blocklist reverts when the account is already blocklisted
    function test_blocklist_revert_statusUnchanged(address account) public {
        vm.assume(account != address(0));
        _blocklist(account);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.BlocklistStatusUnchanged.selector, account, true));
        vm.prank(blocklister);
        stablecoin.blocklist(account);
    }

    // ── blocklist() happy paths ──────────────────────────────────────────────────────────

    /// @notice Verifies blocklist correctly marks an address as blocklisted
    function test_blocklist_success_blocklists(address account) public {
        vm.assume(account != address(0));
        assertFalse(stablecoin.isBlocklisted(account));
        _blocklist(account);
        assertTrue(stablecoin.isBlocklisted(account));
    }

    /// @notice Verifies blocklist emits BlocklistStatusUpdated with blocklisted=true
    function test_blocklist_success_emitsEvent(address account) public {
        vm.assume(account != address(0));
        vm.expectEmit(true, false, false, true);
        emit Blocklist.BlocklistStatusUpdated({account: account, blocklisted: true});
        vm.prank(blocklister);
        stablecoin.blocklist(account);
    }

    // ── unblocklist() reverts ────────────────────────────────────────────────────────────

    /// @notice Verifies unblocklist reverts for any caller without UNBLOCKLIST_ROLE
    function test_unblocklist_revert_unauthorized(address caller) public {
        vm.assume(caller != blocklister);
        _blocklist(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.UNBLOCKLIST_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.unblocklist(alice);
    }

    /// @notice Verifies unblocklist reverts when the account is not currently blocklisted
    function test_unblocklist_revert_statusUnchanged(address account) public {
        vm.assume(account != address(0));
        vm.expectRevert(abi.encodeWithSelector(Blocklist.BlocklistStatusUnchanged.selector, account, false));
        vm.prank(blocklister);
        stablecoin.unblocklist(account);
    }

    // ── unblocklist() happy paths ────────────────────────────────────────────────────────

    /// @notice Verifies unblocklist correctly removes an address from the blocklist
    function test_unblocklist_success_unblocklists(address account) public {
        vm.assume(account != address(0));
        _blocklist(account);
        assertTrue(stablecoin.isBlocklisted(account));
        _unblocklist(account);
        assertFalse(stablecoin.isBlocklisted(account));
    }

    /// @notice Verifies unblocklist emits BlocklistStatusUpdated with blocklisted=false
    function test_unblocklist_success_emitsEvent(address account) public {
        vm.assume(account != address(0));
        _blocklist(account);
        vm.expectEmit(true, false, false, true);
        emit Blocklist.BlocklistStatusUpdated({account: account, blocklisted: false});
        vm.prank(blocklister);
        stablecoin.unblocklist(account);
    }
}
