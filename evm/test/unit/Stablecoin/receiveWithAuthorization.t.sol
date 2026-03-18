// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Blocklist} from "src/lib/Blocklist.sol";
import {ERC3009Upgradeable} from "src/lib/ERC3009Upgradeable.sol";
import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Tests for ERC-3009 receiveWithAuthorization. This is a strict superset of
/// transferWithAuthorization: all tWA revert and success paths apply here, plus the
/// CallerMustBePayee guard which fires first. Reverts are ordered by execution:
/// callerMustBePayee → validAfter → validBefore → nonce used → signature invalid
/// → blocklist (caller/to, from) → pause.
contract StablecoinReceiveWithAuthorizationTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies receiveWithAuthorization reverts when msg.sender is not the payee (to)
    /// @dev CallerMustBePayee: this is the first check; prevents frontrunning by requiring payee submission
    function test_receiveWithAuthorization_revert_callerNotPayee(address caller, uint256 amount) public {
        vm.assume(caller != bob);
        amount = bound(amount, 1, INITIAL_MINT);
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.CallerMustBePayee.selector, caller, bob));
        vm.prank(caller);
        stablecoin.receiveWithAuthorization(alice, bob, amount, 0, type(uint256).max, bytes32(0), sig);
    }

    /// @notice Verifies receiveWithAuthorization reverts when block.timestamp <= validAfter
    /// @dev AuthorizationNotYetValid: matches transferWithAuthorization behavior after payee check
    function test_receiveWithAuthorization_revert_notYetValid(uint256 validAfter) public {
        validAfter = bound(validAfter, block.timestamp, type(uint256).max);
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, 1, validAfter, type(uint256).max, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationNotYetValid.selector, validAfter));
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, 1, validAfter, type(uint256).max, bytes32(0), sig);
    }

    /// @notice Verifies receiveWithAuthorization reverts when block.timestamp >= validBefore
    /// @dev AuthorizationExpired: expired authorizations must be permanently rejected
    function test_receiveWithAuthorization_revert_expired(uint256 validBefore) public {
        validBefore = bound(validBefore, 1, block.timestamp);
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, 1, 0, validBefore, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationExpired.selector, validBefore));
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, 1, 0, validBefore, bytes32(0), sig);
    }

    /// @notice Verifies receiveWithAuthorization reverts when the nonce has already been consumed
    /// @dev AuthorizationAlreadyUsed: nonce-state is permanent; replay must revert on second use
    function test_receiveWithAuthorization_revert_alreadyUsed(bytes32 nonce) public {
        _receiveWithAuth(1, nonce);
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, 1, 0, type(uint256).max, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, 1, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies receiveWithAuthorization reverts when the signature does not match the from address
    /// @dev InvalidAuthorization: SignatureChecker.isValidSignatureNow must reject mismatched signers
    function test_receiveWithAuthorization_revert_invalidSignature(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        // Sign with alice's key but claim from=carol → signature mismatch
        bytes memory wrongSig = _signReceiveAuth(ALICE_KEY, carol, bob, amount, 0, type(uint256).max, nonce);
        vm.expectRevert(ERC3009Upgradeable.InvalidAuthorization.selector);
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(carol, bob, amount, 0, type(uint256).max, nonce, wrongSig);
    }

    /// @notice Verifies receiveWithAuthorization reverts when the caller (payee) is blocklisted
    /// @dev AddressBlocklisted(msg.sender): in receiveWithAuth msg.sender == to; _requireNotBlocklisted(msg.sender) fires first
    function test_receiveWithAuthorization_revert_blocklistedCaller(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(41));
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        _blocklist(bob);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, bob));
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies receiveWithAuthorization reverts when the from address is blocklisted
    /// @dev AddressBlocklisted(from): the signer/payer is blocked regardless of who submits
    function test_receiveWithAuthorization_revert_blocklistedFrom(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(42));
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        _blocklist(alice);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, alice));
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies receiveWithAuthorization reverts when the to address is blocklisted
    /// @dev AddressBlocklisted(to): _requireNotBlocklisted(to) in _update blocks the recipient regardless of caller
    function test_receiveWithAuthorization_revert_blocklistedTo(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(43));
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        _blocklist(bob);
        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, bob));
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies receiveWithAuthorization moves tokens from the signer to the payee
    /// @dev State: balanceOf(from) decreases by value; balanceOf(to) increases by value
    function test_receiveWithAuthorization_success_transfersTokens(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(1));
        uint256 aliceBalBefore = stablecoin.balanceOf(alice);
        uint256 bobBalBefore = stablecoin.balanceOf(bob);
        _receiveWithAuth(amount, nonce);
        assertEq(stablecoin.balanceOf(alice), aliceBalBefore - amount);
        assertEq(stablecoin.balanceOf(bob), bobBalBefore + amount);
    }

    /// @notice Verifies receiveWithAuthorization emits AuthorizationUsed with the correct authorizer and nonce
    /// @dev Event integrity: authorizer == from; nonce must match to allow off-chain tracking
    function test_receiveWithAuthorization_success_emitsAuthorizationUsed(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.expectEmit(true, true, false, false);
        emit ERC3009Upgradeable.AuthorizationUsed(alice, nonce);
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies receiveWithAuthorization marks the nonce as used in authorizationState
    /// @dev State: authorizationState(from, nonce) must return true after a successful receive
    function test_receiveWithAuthorization_success_marksNonceUsed(bytes32 nonce) public {
        assertFalse(stablecoin.authorizationState(alice, nonce));
        _receiveWithAuth(1, nonce);
        assertTrue(stablecoin.authorizationState(alice, nonce));
    }
}
