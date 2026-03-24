// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC3009Upgradeable} from "src/lib/ERC3009Upgradeable.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinCancelAuthorizationTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies cancelAuthorization reverts when the nonce has already been used or canceled
    /// @dev AuthorizationAlreadyUsed: consuming a nonce is permanent; cancel and transfer share the state
    function test_cancelAuthorization_revert_alreadyUsed(bytes32 nonce) public {
        // Consume the nonce via a transfer
        _transferWithAuth(1, nonce);
        assertTrue(stablecoin.authorizationState(alice, nonce));

        bytes memory sig = _signCancelAuth(ALICE_KEY, alice, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        stablecoin.cancelAuthorization(alice, nonce, sig);
    }

    /// @notice Verifies cancelAuthorization reverts when the signature does not match the authorizer
    /// @dev InvalidAuthorization: anyone can submit a cancel, but only with a valid signature from the authorizer
    function test_cancelAuthorization_revert_invalidSignature(bytes32 nonce) public {
        // Sign with bob's key but claim authorizer is alice → mismatch
        bytes memory wrongSig = _signCancelAuth(BOB_KEY, alice, nonce);
        vm.expectRevert(ERC3009Upgradeable.InvalidAuthorization.selector);
        stablecoin.cancelAuthorization(alice, nonce, wrongSig);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies cancelAuthorization marks the nonce as used so it cannot be used for a transfer
    /// @dev State: authorizationState(authorizer, nonce) returns true; subsequent transferWithAuthorization reverts
    function test_cancelAuthorization_success_marksNonceUsed(bytes32 nonce) public {
        assertFalse(stablecoin.authorizationState(alice, nonce));

        bytes memory cancelSig = _signCancelAuth(ALICE_KEY, alice, nonce);
        stablecoin.cancelAuthorization(alice, nonce, cancelSig);
        assertTrue(stablecoin.authorizationState(alice, nonce));

        // Confirm the nonce cannot be used for a transfer
        bytes memory transferSig = _signTransferAuth(ALICE_KEY, alice, bob, 1, 0, type(uint256).max, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, 1, 0, type(uint256).max, nonce, transferSig);
    }

    /// @notice Verifies cancelAuthorization emits AuthorizationCanceled with the correct authorizer and nonce
    /// @dev Event integrity: both fields must match to allow off-chain listeners to track canceled nonces
    function test_cancelAuthorization_success_emitsAuthorizationCanceled(bytes32 nonce) public {
        bytes memory sig = _signCancelAuth(ALICE_KEY, alice, nonce);
        vm.expectEmit(true, true, false, false);
        emit ERC3009Upgradeable.AuthorizationCanceled({authorizer: alice, nonce: nonce});
        stablecoin.cancelAuthorization(alice, nonce, sig);
    }

    /// @notice Verifies the external (v, r, s) overload delegates correctly to the bytes-signature variant
    /// @dev Coverage: the v/r/s overload is a thin wrapper; one passing call is sufficient to confirm delegation
    function test_cancelAuthorization_success_vrsOverload(bytes32 nonce) public {
        assertFalse(stablecoin.authorizationState(alice, nonce));
        bytes32 digest = _cancelAuthDigest(alice, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, digest);
        stablecoin.cancelAuthorization(alice, nonce, v, r, s);
        assertTrue(stablecoin.authorizationState(alice, nonce));
    }
}
