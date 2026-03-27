// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Blocklist} from "src/lib/Blocklist.sol";
import {Stablecoin} from "src/Stablecoin.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Tests for burnWithMemo.
contract StablecoinBurnWithMemoTest is StablecoinTest {
    bytes32 internal constant MEMO = keccak256("burn-memo");

    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies burnWithMemo reverts for any caller without BURN_ROLE
    function test_burnWithMemo_revert_unauthorized(address caller) public {
        vm.assume(caller != burner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.BURN_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.burnWithMemo(1, MEMO);
    }

    /// @notice Verifies burnWithMemo reverts when the caller is blocklisted
    function test_burnWithMemo_revert_callerBlocklisted(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _blocklist(burner);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, burner));
        vm.prank(burner);
        stablecoin.burnWithMemo(amount, MEMO);
    }

    /// @notice Verifies burnWithMemo reverts when the contract is paused
    function test_burnWithMemo_revert_whenPaused(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(burner);
        stablecoin.burnWithMemo(amount, MEMO);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies burnWithMemo reduces total supply
    function test_burnWithMemo_success_reducesSupply(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        uint256 supplyBefore = stablecoin.totalSupply();
        vm.prank(burner);
        stablecoin.burnWithMemo(amount, MEMO);
        assertEq(stablecoin.totalSupply(), supplyBefore - amount);
    }

    /// @notice Verifies burnWithMemo emits both Burned and Memo events
    function test_burnWithMemo_success_emitsEvents(uint256 amount, bytes32 memo) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.expectEmit(true, false, false, true);
        emit Stablecoin.Burned({burner: burner, amount: amount});
        vm.expectEmit(true, false, false, false);
        emit Stablecoin.Memo({memo: memo});
        vm.prank(burner);
        stablecoin.burnWithMemo(amount, memo);
    }
}
