// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {MintRateLimit} from "src/lib/MintRateLimit.sol";
import {StablecoinTest} from "test/lib/StablecoinTest.sol";
import {Stablecoin} from "src/Stablecoin.sol";

contract StablecoinMintTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies mint reverts for any caller without MINT_ROLE
    /// @dev Access control: onlyRole(MINT_ROLE) must reject all unauthorized callers
    function test_mint_revert_unauthorized(address caller) public {
        vm.assume(caller != minter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.MINT_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.mint(alice, 1);
    }

    /// @notice Verifies mint reverts when the requested amount exceeds the minter's remaining capacity
    /// @dev MintLimitExceeded: capacity is checked before _mint; no partial state changes should occur
    function test_mint_revert_mintLimitExceeded(uint256 amount) public {
        uint256 remaining = stablecoin.currentMintLimit(minter);
        amount = bound(amount, remaining + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(MintRateLimit.MintLimitExceeded.selector, minter, amount, remaining));
        vm.prank(minter);
        stablecoin.mint(alice, amount);
    }

    /// @notice Verifies mint reverts when the contract is paused
    /// @dev EnforcedPause fires in super._update after blocklist checks; blocklist checks pass first
    function test_mint_revert_whenPaused(uint256 amount) public {
        uint256 remaining = stablecoin.currentMintLimit(minter);
        amount = bound(amount, 1, remaining);
        _pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(minter);
        stablecoin.mint(alice, amount);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies mint increases the recipient's token balance by exactly the minted amount
    /// @dev State invariant: balanceOf(to) increases by amount after each successful mint
    function test_mint_success_updatesBalance(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 1, stablecoin.currentMintLimit(minter));
        uint256 balBefore = stablecoin.balanceOf(to);
        _mint(to, amount);
        assertEq(stablecoin.balanceOf(to), balBefore + amount);
    }

    /// @notice Verifies mint increases the total token supply by exactly the minted amount
    /// @dev State invariant: totalSupply() increases by amount; no supply is created or destroyed
    function test_mint_success_increasesTotalSupply(uint256 amount) public {
        amount = bound(amount, 1, stablecoin.currentMintLimit(minter));
        uint256 supplyBefore = stablecoin.totalSupply();
        _mint(alice, amount);
        assertEq(stablecoin.totalSupply(), supplyBefore + amount);
    }

    /// @notice Verifies mint emits the Minted event with the correct minter, recipient, and amount
    /// @dev Event integrity: minter == msg.sender, to and amount must match arguments exactly
    function test_mint_success_emitsMinted(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 1, stablecoin.currentMintLimit(minter));
        vm.expectEmit(true, true, false, true);
        emit Stablecoin.Minted(minter, to, amount);
        vm.prank(minter);
        stablecoin.mint(to, amount);
    }

    /// @notice Verifies mint deducts the minted amount from the minter's remaining rate-limit capacity
    /// @dev Rate limit: remaining capacity must decrease by amount; replenishment logic is separate
    function test_mint_success_consumesRateLimit(uint256 amount) public {
        uint256 limitBefore = stablecoin.currentMintLimit(minter);
        amount = bound(amount, 1, limitBefore);
        _mint(alice, amount);
        assertEq(stablecoin.currentMintLimit(minter), limitBefore - amount);
    }
}
