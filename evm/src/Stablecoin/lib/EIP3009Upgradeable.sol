// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title EIP3009Upgradeable
/// @author Coinbase
/// @notice ERC-3009 Transfer With Authorization implementation using ERC-7201 namespaced storage.
///
/// @dev Enables meta-transaction transfers via signed EIP-712 authorizations. Uses random 32-byte
/// nonces (not sequential) to allow multiple concurrent authorizations. Inherits `ERC20Upgradeable`
/// for `_transfer` and `EIP712Upgradeable` for `_hashTypedDataV4`.
abstract contract EIP3009Upgradeable is ERC20Upgradeable, EIP712Upgradeable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for ERC-3009 authorization nonces.
    /// @custom:storage-location erc7201:coinbase.storage.Stablecoin.ERC3009
    struct Erc3009Layout {
        /// @dev Maps each authorizer to their nonce usage status.
        mapping(address authorizer => mapping(bytes32 nonce => bool used)) authorizationStates;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.Stablecoin.ERC3009")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC3009_STORAGE_LOCATION =
        0x427d307c31a45430da5a55d786be96204d2bd18e654f089714e3af8ce9abb000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 private constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    // keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 private constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    // keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")
    bytes32 private constant CANCEL_AUTHORIZATION_TYPEHASH =
        0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an authorization nonce is consumed by a transfer.
    ///
    /// @param authorizer The address that signed the authorization.
    /// @param nonce      The nonce that was consumed.
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    /// @notice Emitted when an authorization nonce is canceled.
    ///
    /// @param authorizer The address that canceled the authorization.
    /// @param nonce      The nonce that was canceled.
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /// @notice Thrown when the authorization nonce has already been used or canceled.
    ///
    /// @param authorizer The authorizer address.
    /// @param nonce      The already-used nonce.
    error AuthorizationAlreadyUsed(address authorizer, bytes32 nonce);

    /// @notice Thrown when `block.timestamp` is before the authorization's `validAfter`.
    ///
    /// @param validAfter The earliest allowed timestamp.
    error AuthorizationNotYetValid(uint256 validAfter);

    /// @notice Thrown when `block.timestamp` is after the authorization's `validBefore`.
    ///
    /// @param validBefore The latest allowed timestamp.
    error AuthorizationExpired(uint256 validBefore);

    /// @notice Thrown when `receiveWithAuthorization` is called by someone other than the payee.
    ///
    /// @param caller The actual caller.
    /// @param payee  The expected caller (the `to` address).
    error CallerMustBePayee(address caller, address payee);

    /// @notice Thrown when the recovered signer does not match the expected authorizer.
    error InvalidAuthorization();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Executes a transfer from `from` to `to` using a signed authorization.
    ///
    /// @dev Anyone may submit this transaction. The authorization is validated via EIP-712 signature
    /// recovery. The transfer goes through `_transfer` -> `_update`, so blacklist and pause checks apply.
    ///
    /// @param from        The payer (signer of the authorization).
    /// @param to          The payee (recipient of the transfer).
    /// @param value       The amount to transfer.
    /// @param validAfter  The earliest unix timestamp at which the authorization is valid.
    /// @param validBefore The latest unix timestamp at which the authorization is valid.
    /// @param nonce       A unique random 32-byte nonce.
    /// @param v           ECDSA signature component.
    /// @param r           ECDSA signature component.
    /// @param s           ECDSA signature component.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _transferWithAuthorization({
            typehash: TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            from: from,
            to: to,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });
    }

    /// @notice Executes a transfer from `from` to `to` where only `to` may submit the transaction.
    ///
    /// @dev This prevents front-running by ensuring only the intended recipient can execute the transfer.
    /// The authorization is validated via EIP-712 signature recovery.
    ///
    /// @param from        The payer (signer of the authorization).
    /// @param to          The payee (recipient and required msg.sender).
    /// @param value       The amount to transfer.
    /// @param validAfter  The earliest unix timestamp at which the authorization is valid.
    /// @param validBefore The latest unix timestamp at which the authorization is valid.
    /// @param nonce       A unique random 32-byte nonce.
    /// @param v           ECDSA signature component.
    /// @param r           ECDSA signature component.
    /// @param s           ECDSA signature component.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (msg.sender != to) revert CallerMustBePayee({caller: msg.sender, payee: to});
        _transferWithAuthorization({
            typehash: RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
            from: from,
            to: to,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });
    }

    /// @notice Cancels a previously unused authorization nonce.
    ///
    /// @dev The authorizer signs a `CancelAuthorization` message to void a nonce before it is used.
    ///
    /// @param authorizer The address that originally signed the authorization.
    /// @param nonce      The nonce to cancel.
    /// @param v          ECDSA signature component.
    /// @param r          ECDSA signature component.
    /// @param s          ECDSA signature component.
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        _requireUnusedAuthorization({authorizer: authorizer, nonce: nonce});

        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce));
        _requireValidSignature({authorizer: authorizer, structHash: structHash, v: v, r: r, s: s});

        _getErc3009Layout().authorizationStates[authorizer][nonce] = true;
        emit AuthorizationCanceled({authorizer: authorizer, nonce: nonce});
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns whether a given authorization nonce has been used or canceled.
    ///
    /// @param authorizer The authorizer address.
    /// @param nonce      The nonce to query.
    ///
    /// @return True if the nonce has been used or canceled.
    function authorizationState(address authorizer, bytes32 nonce) public view virtual returns (bool) {
        return _getErc3009Layout().authorizationStates[authorizer][nonce];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates and executes a signed transfer authorization.
    ///
    /// @param typehash   The EIP-712 typehash for the authorization type.
    /// @param from        The payer (signer of the authorization).
    /// @param to          The payee (recipient of the transfer).
    /// @param value       The amount to transfer.
    /// @param validAfter  The earliest unix timestamp at which the authorization is valid.
    /// @param validBefore The latest unix timestamp at which the authorization is valid.
    /// @param nonce       A unique random 32-byte nonce.
    /// @param v           ECDSA signature component.
    /// @param r           ECDSA signature component.
    /// @param s           ECDSA signature component.
    function _transferWithAuthorization(
        bytes32 typehash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        _requireValidAuthorization({authorizer: from, validAfter: validAfter, validBefore: validBefore, nonce: nonce});

        bytes32 structHash = keccak256(abi.encode(typehash, from, to, value, validAfter, validBefore, nonce));
        _requireValidSignature({authorizer: from, structHash: structHash, v: v, r: r, s: s});

        _markAuthorizationUsed({authorizer: from, nonce: nonce});
        _transfer(from, to, value);
    }

    /// @notice Validates time window and nonce freshness for an authorization.
    ///
    /// @param authorizer  The authorizer address.
    /// @param validAfter  The earliest valid timestamp.
    /// @param validBefore The latest valid timestamp.
    /// @param nonce       The nonce to validate.
    function _requireValidAuthorization(address authorizer, uint256 validAfter, uint256 validBefore, bytes32 nonce)
        private
        view
    {
        if (block.timestamp <= validAfter) revert AuthorizationNotYetValid({validAfter: validAfter});
        if (block.timestamp >= validBefore) revert AuthorizationExpired({validBefore: validBefore});
        _requireUnusedAuthorization({authorizer: authorizer, nonce: nonce});
    }

    /// @notice Reverts if the given nonce has already been used or canceled.
    ///
    /// @param authorizer The authorizer address.
    /// @param nonce      The nonce to check.
    function _requireUnusedAuthorization(address authorizer, bytes32 nonce) private view {
        if (authorizationState({authorizer: authorizer, nonce: nonce})) {
            revert AuthorizationAlreadyUsed({authorizer: authorizer, nonce: nonce});
        }
    }

    /// @notice Recovers the signer from an EIP-712 struct hash and verifies it matches the authorizer.
    ///
    /// @param authorizer The expected signer.
    /// @param structHash The EIP-712 struct hash.
    /// @param v          ECDSA signature component.
    /// @param r          ECDSA signature component.
    /// @param s          ECDSA signature component.
    function _requireValidSignature(address authorizer, bytes32 structHash, uint8 v, bytes32 r, bytes32 s)
        private
        view
    {
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);
        if (signer != authorizer) revert InvalidAuthorization();
    }

    /// @notice Marks a nonce as used and emits the `AuthorizationUsed` event.
    ///
    /// @param authorizer The authorizer address.
    /// @param nonce      The nonce to mark as used.
    function _markAuthorizationUsed(address authorizer, bytes32 nonce) private {
        _getErc3009Layout().authorizationStates[authorizer][nonce] = true;
        emit AuthorizationUsed({authorizer: authorizer, nonce: nonce});
    }

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getErc3009Layout() private pure returns (Erc3009Layout storage $) {
        assembly {
            $.slot := ERC3009_STORAGE_LOCATION
        }
    }
}
