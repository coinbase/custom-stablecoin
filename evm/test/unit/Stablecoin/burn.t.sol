// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Blocklist} from "src/lib/Blocklist.sol";
import {StablecoinTest} from "test/lib/StablecoinTest.sol";
import {Stablecoin} from "src/Stablecoin.sol";

contract StablecoinBurnTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies burn reverts for any caller without BURN_ROLE
    /// @dev Access control: onlyRole(BURN_ROLE) must reject all unauthorized callers
    function test_burn_revert_unauthorized(address caller) public {
        vm.assume(caller != burner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.BURN_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.burn(1);
    }

    /// @notice Verifies burn reverts when the caller is blocklisted
    /// @dev AddressBlocklisted: _requireNotBlocklisted(msg.sender) fires in _update before the pause check
    function test_burn_revert_callerBlocklisted(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _blocklist(burner);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, burner));
        vm.prank(burner);
        stablecoin.burn(amount);
    }

    /// @notice Verifies burn reverts when the contract is paused
    /// @dev EnforcedPause fires in super._update after blocklist checks pass
    function test_burn_revert_whenPaused(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        _pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(burner);
        stablecoin.burn(amount);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies burn reduces the total token supply by exactly the burned amount
    /// @dev State invariant: totalSupply() decreases by amount; no tokens are redirected
    function test_burn_success_reducesSupply(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        uint256 supplyBefore = stablecoin.totalSupply();
        _burn(burner, amount);
        assertEq(stablecoin.totalSupply(), supplyBefore - amount);
    }

    /// @notice Verifies burn emits the Burned event with the correct burner and amount
    /// @dev Event integrity: burner == msg.sender; amount must match the argument exactly
    function test_burn_success_emitsBurned(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.expectEmit(true, false, false, true);
        emit Stablecoin.Burned(burner, amount);
        vm.prank(burner);
        stablecoin.burn(amount);
    }
}
