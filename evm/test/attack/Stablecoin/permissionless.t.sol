// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {StablecoinTest} from "test/lib/StablecoinTest.sol";
import {ERC3009Upgradeable} from "src/lib/ERC3009Upgradeable.sol";

/// @dev Attack tests for permissionless entry points. transferWithAuthorization and
/// cancelAuthorization have no caller restriction — any address may submit them.
/// These tests verify that the absence of a caller guard cannot be exploited.
contract StablecoinPermissionlessTest is StablecoinTest {
    // ── cancelAuthorization abuse ─────────────────────────────────────────────────────────

    /// @notice Verifies an attacker cannot cancel another user's valid authorization without a valid signature
    /// @dev Permissionless: anyone can call cancelAuthorization, but only with a valid sig from the authorizer
    function test_attack_permissionless_cannotCancelWithoutValidSignature(address attacker_, bytes32 nonce) public {
        vm.assume(attacker_ != alice);
        // Attacker signs the cancel with bob's key, not alice's — mismatch
        bytes memory wrongSig = _signCancelAuth(BOB_KEY, alice, nonce);
        vm.expectRevert(ERC3009Upgradeable.InvalidAuthorization.selector);
        vm.prank(attacker_);
        stablecoin.cancelAuthorization(alice, nonce, wrongSig);
    }

    /// @notice Verifies an attacker cannot grief a user by pre-canceling an authorization they obtained
    /// @dev Degrees of freedom: attacker observes the nonce from a signed auth and attempts to cancel it first
    function test_attack_permissionless_cancelGriefRequiresValidSig(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        // Alice signs a transfer authorization; attacker observes it
        bytes memory transferSig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);

        // Attacker tries to cancel alice's nonce using their own (bob's) key — fails
        bytes memory attackerCancelSig = _signCancelAuth(BOB_KEY, alice, nonce);
        vm.expectRevert(ERC3009Upgradeable.InvalidAuthorization.selector);
        vm.prank(attacker);
        stablecoin.cancelAuthorization(alice, nonce, attackerCancelSig);

        // Original transfer authorization is still valid
        _transferWithAuth(relayer, alice, bob, amount, 0, type(uint256).max, nonce, transferSig);
        assertTrue(stablecoin.authorizationState(alice, nonce));
    }

    // ── transferWithAuthorization frontrunning ────────────────────────────────────────────

    /// @notice Verifies frontrunning a transferWithAuthorization does not let the frontrunner steal funds
    /// @dev Frontrun: attacker copies the signed tx from mempool; the transfer still goes to the correct `to`
    function test_attack_permissionless_frontrunTransferWithAuthorization(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(0xbad));

        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);

        uint256 bobBalBefore = stablecoin.balanceOf(bob);
        uint256 attackerBalBefore = stablecoin.balanceOf(attacker);

        // Attacker front-runs by submitting the signed message themselves
        vm.prank(attacker);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);

        // Tokens still go to bob (the specified `to`), not to attacker
        assertEq(stablecoin.balanceOf(bob), bobBalBefore + amount);
        assertEq(stablecoin.balanceOf(attacker), attackerBalBefore);
    }

    // ── receiveWithAuthorization caller restriction ───────────────────────────────────────

    /// @notice Verifies that only the payee (to) can submit a receiveWithAuthorization
    /// @dev Payee guard: unlike transferWithAuthorization, frontrunning receiveWithAuth is blocked by design
    function test_attack_permissionless_receiveRequiresPayeeSubmission(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(0xbad));

        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);

        // Attacker (not bob) cannot submit receiveWithAuthorization
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.CallerMustBePayee.selector, attacker, bob));
        vm.prank(attacker);
        stablecoin.receiveWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    // ── Nonce race conditions ─────────────────────────────────────────────────────────────

    /// @notice Verifies that two concurrent authorizations with the same nonce cannot both succeed
    /// @dev Race condition: the second submission must revert with AuthorizationAlreadyUsed
    function test_attack_permissionless_nonceRaceCondition(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        // First submission succeeds
        _transferWithAuth(amount, nonce);
        assertTrue(stablecoin.authorizationState(alice, nonce));

        // Second submission with same nonce fails (regardless of who submits)
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }
}
