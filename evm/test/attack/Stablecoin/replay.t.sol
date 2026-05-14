// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC3009Upgradeable} from "src/lib/ERC3009Upgradeable.sol";
import {MutableBeaconProxy} from "src/MutableBeaconProxy.sol";
import {Stablecoin} from "src/Stablecoin.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Replay attack tests for ERC-3009 and ERC-2612 (permit) signed authorizations.
/// Verifies that nonces are permanently consumed and domain separators bind to chain and contract.
contract StablecoinReplayTest is StablecoinTest {
    // ── Same-context replay ───────────────────────────────────────────────────────────────

    /// @notice Verifies a transferWithAuthorization nonce cannot be submitted a second time
    /// @dev Replay: second submission with the same nonce must revert with AuthorizationAlreadyUsed
    function test_attack_replay_transferWithAuthorization_sameNonce(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        // First submission succeeds
        _transferWithAuth(amount, nonce);
        assertTrue(stablecoin.authorizationState(alice, nonce));

        // Second submission with the same nonce reverts
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Verifies a canceled nonce cannot subsequently be used for a transfer
    /// @dev Cross-operation replay: cancelAuthorization and transferWithAuthorization share nonce state
    function test_attack_replay_cancelThenTransfer(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        // Cancel the nonce
        bytes memory cancelSig = _signCancelAuth(ALICE_KEY, alice, nonce);
        stablecoin.cancelAuthorization(alice, nonce, cancelSig);
        assertTrue(stablecoin.authorizationState(alice, nonce));

        // Attempt to use the canceled nonce for a transfer reverts
        bytes memory transferSig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, transferSig);
    }

    /// @notice Verifies a transferWithAuthorization nonce cannot be reused as a receiveWithAuthorization
    /// @dev Cross-type replay: both functions share the same nonce space via authorizationState
    function test_attack_replay_transferNonceNotReusableAsReceive(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        // Consume the nonce via transferWithAuthorization
        _transferWithAuth(amount, nonce);
        assertTrue(stablecoin.authorizationState(alice, nonce));

        // Attempt to reuse the nonce in receiveWithAuthorization reverts
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, 1, 0, type(uint256).max, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, 1, 0, type(uint256).max, nonce, sig);
    }

    // ── Cross-chain replay ────────────────────────────────────────────────────────────────

    /// @notice Verifies a signature created on one chain is rejected on a different chain
    /// @dev Cross-chain replay: domain separator encodes chainId; signature over wrong chainId is invalid
    function test_attack_replay_crossChain(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        // Sign with the current chain's domain separator
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);

        // Switch to a different chain; domain separator changes
        vm.chainId(block.chainid + 1);

        // Signature is now invalid (digest was computed with the old chain's separator)
        vm.expectRevert(ERC3009Upgradeable.InvalidAuthorization.selector);
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    // ── Cross-contract replay ─────────────────────────────────────────────────────────────

    /// @notice Verifies a signature from one stablecoin deployment is rejected by a different deployment
    /// @dev Cross-contract replay: domain separator encodes the verifying contract address
    function test_attack_replay_crossContract(bytes32 nonce, uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        // Sign a transfer auth for the original stablecoin
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);

        // Deploy a second stablecoin with a different address → different domain separator
        Stablecoin impl2 = new Stablecoin();
        bytes memory initData = abi.encodeCall(Stablecoin.initialize, (TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, admin));
        Stablecoin stablecoin2 = Stablecoin(address(new MutableBeaconProxy(address(beacon), initData)));

        // Same signature is invalid on stablecoin2
        vm.expectRevert(ERC3009Upgradeable.InvalidAuthorization.selector);
        vm.prank(relayer);
        stablecoin2.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);

        // Suppress unused variable warning
        impl2;
    }

    // ── ERC-2612 permit replay ────────────────────────────────────────────────────────────

    /// @notice Verifies an ERC-2612 permit cannot be replayed after the nonce is consumed
    /// @dev Permit replay: OZ ERC20Permit uses sequential nonces; same nonce must be rejected
    function test_attack_replay_permit_sameNonce(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        uint256 deadline = type(uint256).max;
        uint256 nonce = stablecoin.nonces(alice);

        // Build and sign a permit
        bytes32 permitTypehash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(permitTypehash, alice, bob, amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", stablecoin.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_KEY, digest);

        // First permit succeeds; nonce increments
        stablecoin.permit(alice, bob, amount, deadline, v, r, s);
        assertEq(stablecoin.nonces(alice), nonce + 1);

        // Replay with same signature (now with stale nonce 0) fails
        vm.expectRevert();
        stablecoin.permit(alice, bob, amount, deadline, v, r, s);
    }
}
