// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Sanctionable} from "src/lib/Sanctionable.sol";
import {ERC3009Upgradeable} from "src/lib/ERC3009Upgradeable.sol";
import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Tests for ERC-3009 transferWithAuthorization. Reverts are ordered by execution:
/// validAfter → validBefore → nonce used → signature invalid → sanction (caller, from, to) → pause.
contract StablecoinTransferWithAuthorizationTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies transferWithAuthorization reverts when block.timestamp <= validAfter
    /// @dev AuthorizationNotYetValid: authorization must not be submitted before its activation time
    function test_transferWithAuthorization_revert_notYetValid(uint256 validAfter) public {
        validAfter = bound(validAfter, block.timestamp, type(uint256).max);
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, 1, validAfter, type(uint256).max, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationNotYetValid.selector, validAfter));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, 1, validAfter, type(uint256).max, bytes32(0), sig);
    }

    /// @notice Verifies transferWithAuthorization reverts when block.timestamp >= validBefore
    /// @dev AuthorizationExpired: expired authorizations must be permanently rejected
    function test_transferWithAuthorization_revert_expired(uint256 validBefore) public {
        validBefore = bound(validBefore, 1, block.timestamp);
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, 1, 0, validBefore, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationExpired.selector, validBefore));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, 1, 0, validBefore, bytes32(0), sig);
    }

    /// @notice Verifies transferWithAuthorization reverts when the nonce has already been consumed
    /// @dev AuthorizationAlreadyUsed: nonce-state is permanent; replay must revert on second use
    function test_transferWithAuthorization_revert_alreadyUsed(bytes32 nonce) public {
        _transferWithAuth(1, nonce);
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, 1, 0, type(uint256).max, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, 1, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies transferWithAuthorization reverts when the signature does not match the from address
    /// @dev InvalidAuthorization: SignatureChecker.isValidSignatureNow must reject mismatched signers
    function test_transferWithAuthorization_revert_invalidSignature(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        // Sign with bob's key, but claim from=alice → signature mismatch
        bytes memory wrongSig = _signTransferAuth(BOB_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.expectRevert(ERC3009Upgradeable.InvalidAuthorization.selector);
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, wrongSig);
    }

    /// @notice Verifies transferWithAuthorization reverts when the relayer (msg.sender) is sanctioned
    /// @dev AddressSanctioned(msg.sender): relayer sanction is the first _update check after auth validation
    function test_transferWithAuthorization_revert_sanctionedCaller(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(42));
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        _sanction(relayer);
        vm.expectRevert(abi.encodeWithSelector(Sanctionable.AddressSanctioned.selector, relayer));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies transferWithAuthorization reverts when the from address is sanctioned
    /// @dev AddressSanctioned(from): the token holder/signer is blocked regardless of who relays
    function test_transferWithAuthorization_revert_sanctionedFrom(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(42));
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        _sanction(alice);
        vm.expectRevert(abi.encodeWithSelector(Sanctionable.AddressSanctioned.selector, alice));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies transferWithAuthorization reverts when the to address is sanctioned
    /// @dev AddressSanctioned(to): sanctioned recipients cannot receive tokens through any path
    function test_transferWithAuthorization_revert_sanctionedTo(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(42));
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        _sanction(bob);
        vm.expectRevert(abi.encodeWithSelector(Sanctionable.AddressSanctioned.selector, bob));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies transferWithAuthorization moves tokens from the signer to the recipient
    /// @dev State: balanceOf(from) decreases by value; balanceOf(to) increases by value
    function test_transferWithAuthorization_success_transfersTokens(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(1));
        uint256 aliceBalBefore = stablecoin.balanceOf(alice);
        uint256 bobBalBefore = stablecoin.balanceOf(bob);
        _transferWithAuth(amount, nonce);
        assertEq(stablecoin.balanceOf(alice), aliceBalBefore - amount);
        assertEq(stablecoin.balanceOf(bob), bobBalBefore + amount);
    }

    /// @notice Verifies transferWithAuthorization emits AuthorizationUsed with the correct authorizer and nonce
    /// @dev Event integrity: authorizer == from; nonce must match to allow off-chain tracking
    function test_transferWithAuthorization_success_emitsAuthorizationUsed(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.expectEmit(true, true, false, false);
        emit ERC3009Upgradeable.AuthorizationUsed(alice, nonce);
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies transferWithAuthorization marks the nonce as used in authorizationState
    /// @dev State: authorizationState(from, nonce) must return true after a successful transfer
    function test_transferWithAuthorization_success_marksNonceUsed(bytes32 nonce) public {
        assertFalse(stablecoin.authorizationState(alice, nonce));
        _transferWithAuth(1, nonce);
        assertTrue(stablecoin.authorizationState(alice, nonce));
    }
}
