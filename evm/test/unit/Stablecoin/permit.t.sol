// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Blocklist} from "src/lib/Blocklist.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinPermitTest is StablecoinTest {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function _permitDigest(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", stablecoin.DOMAIN_SEPARATOR(), structHash));
    }

    function _signPermit(
        uint256 signerKey,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 digest = _permitDigest(owner, spender, value, nonce, deadline);
        (v, r, s) = vm.sign(signerKey, digest);
    }

    // ── Blocklist reverts ────────────────────────────────────────────────────────────────

    /// @notice Verifies permit reverts when the owner is blocklisted
    function test_permit_revert_ownerBlocklisted(uint256 value) public {
        _blocklist(alice);
        uint256 nonce = stablecoin.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ALICE_KEY, alice, bob, value, nonce, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, alice));
        stablecoin.permit(alice, bob, value, type(uint256).max, v, r, s);
    }

    /// @notice Verifies permit reverts when the spender is blocklisted
    function test_permit_revert_spenderBlocklisted(uint256 value) public {
        _blocklist(bob);
        uint256 nonce = stablecoin.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ALICE_KEY, alice, bob, value, nonce, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, bob));
        stablecoin.permit(alice, bob, value, type(uint256).max, v, r, s);
    }

    /// @notice Verifies permit reverts when the caller (msg.sender) is blocklisted
    function test_permit_revert_callerBlocklisted(uint256 value) public {
        _blocklist(carol);
        uint256 nonce = stablecoin.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ALICE_KEY, alice, bob, value, nonce, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Blocklist.AddressBlocklisted.selector, carol));
        vm.prank(carol);
        stablecoin.permit(alice, bob, value, type(uint256).max, v, r, s);
    }

    // ── Happy path ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies permit succeeds when no addresses are blocklisted
    function test_permit_success_setsAllowance(uint256 value) public {
        uint256 nonce = stablecoin.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(ALICE_KEY, alice, bob, value, nonce, type(uint256).max);

        stablecoin.permit(alice, bob, value, type(uint256).max, v, r, s);
        assertEq(stablecoin.allowance(alice, bob), value);
    }
}
