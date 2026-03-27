// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title ERC3009Upgradeable
/// @notice ERC-3009 Transfer With Authorization implementation using ERC-7201 namespaced storage.
///
/// @dev Enables meta-transaction transfers via signed EIP-712 authorizations. Uses random 32-byte
/// nonces (not sequential) to allow multiple concurrent authorizations. Inherits `ERC20Upgradeable`
/// for `_transfer` and `EIP712Upgradeable` for `_hashTypedDataV4`.
/// @author Coinbase
abstract contract ERC3009Upgradeable is ERC20Upgradeable, EIP712Upgradeable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for ERC-3009 authorization nonces.
    /// @custom:storage-location erc7201:coinbase.storage.Stablecoin.ERC3009Upgradeable
    struct ERC3009Layout {
        /// @dev Maps each authorizer to their nonce usage status.
        mapping(address authorizer => mapping(bytes32 nonce => bool used)) authorizationState;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.Stablecoin.ERC3009Upgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _ERC3009_STORAGE_LOCATION =
        0xb8aebb83576e62291cd82363e38e83ae9b2360a49a089992dbdffe80b8e41600;

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

    /// @notice Thrown when `block.timestamp` is not strictly after the authorization's `validAfter`.
    ///
    /// @param validAfter The earliest allowed timestamp (exclusive).
    error AuthorizationNotYetValid(uint256 validAfter);

    /// @notice Thrown when `block.timestamp` is not strictly before the authorization's `validBefore`.
    ///
    /// @param validBefore The latest allowed timestamp (exclusive).
    error AuthorizationExpired(uint256 validBefore);

    /// @notice Thrown when `receiveWithAuthorization` is called by someone other than the payee.
    ///
    /// @param caller The actual caller.
    /// @param payee  The expected caller (the `to` address).
    error CallerMustBePayee(address caller, address payee);

    /// @notice Thrown when the signature is invalid for the expected authorizer.
    error InvalidAuthorization();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Executes a transfer from `from` to `to` using a signed authorization.
    ///
    /// @dev Anyone may submit this transaction. The authorization is validated via EIP-712 signature
    /// recovery. The transfer goes through `_transfer` -> `_update`, so blocklist and pause checks apply.
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
        transferWithAuthorization({
            from: from,
            to: to,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(r, s, v)
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
        receiveWithAuthorization({
            from: from,
            to: to,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: abi.encodePacked(r, s, v)
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
        cancelAuthorization({authorizer: authorizer, nonce: nonce, signature: abi.encodePacked(r, s, v)});
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Executes a transfer from `from` to `to` using a signed authorization.
    ///
    /// @dev Anyone may submit this transaction. Validates the authorization using
    /// `SignatureChecker.isValidSignatureNow`, which supports both 65-byte ECDSA signatures
    /// from EOAs and ERC-1271 signatures from smart contract wallets.
    /// The transfer goes through `_transfer` -> `_update`, so blocklist and pause checks apply.
    ///
    /// @param from        The payer (signer of the authorization).
    /// @param to          The payee (recipient of the transfer).
    /// @param value       The amount to transfer.
    /// @param validAfter  The earliest unix timestamp at which the authorization is valid.
    /// @param validBefore The latest unix timestamp at which the authorization is valid.
    /// @param nonce       A unique random 32-byte nonce.
    /// @param signature   Packed signature over the EIP-712 authorization struct.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) public {
        _transferWithAuthorization({
            typehash: TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            from: from,
            to: to,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: signature
        });
    }

    /// @notice Executes a transfer from `from` to `to` where only `to` may submit the transaction.
    ///
    /// @dev This prevents front-running by ensuring only the intended recipient can execute the transfer.
    /// Validates the authorization using `SignatureChecker.isValidSignatureNow`, which supports both
    /// 65-byte ECDSA signatures from EOAs and ERC-1271 signatures from smart contract wallets.
    ///
    /// @param from        The payer (signer of the authorization).
    /// @param to          The payee (recipient and required msg.sender).
    /// @param value       The amount to transfer.
    /// @param validAfter  The earliest unix timestamp at which the authorization is valid.
    /// @param validBefore The latest unix timestamp at which the authorization is valid.
    /// @param nonce       A unique random 32-byte nonce.
    /// @param signature   Packed signature over the EIP-712 authorization struct.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) public {
        if (msg.sender != to) revert CallerMustBePayee({caller: msg.sender, payee: to});
        _transferWithAuthorization({
            typehash: RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
            from: from,
            to: to,
            value: value,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            signature: signature
        });
    }

    /// @notice Cancels a previously unused authorization nonce.
    ///
    /// @dev The authorizer signs a `CancelAuthorization` message to void a nonce before it is used.
    /// Validates using `SignatureChecker.isValidSignatureNow`, which supports both 65-byte ECDSA
    /// signatures from EOAs and ERC-1271 signatures from smart contract wallets.
    ///
    /// @param authorizer The address that originally signed the authorization.
    /// @param nonce      The nonce to cancel.
    /// @param signature  Packed signature over the EIP-712 cancel authorization struct.
    function cancelAuthorization(address authorizer, bytes32 nonce, bytes memory signature) public {
        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce));
        _consumeAuthorization({authorizer: authorizer, nonce: nonce, structHash: structHash, signature: signature});
        emit AuthorizationCanceled({authorizer: authorizer, nonce: nonce});
    }

    /// @notice Returns whether a given authorization nonce has been used or canceled.
    ///
    /// @param authorizer The authorizer address.
    /// @param nonce      The nonce to query.
    ///
    /// @return True if the nonce has been used or canceled.
    function authorizationState(address authorizer, bytes32 nonce) public view virtual returns (bool) {
        return _getERC3009Layout().authorizationState[authorizer][nonce];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Validates and executes a signed transfer authorization.
    ///
    /// @param typehash    The EIP-712 typehash for the authorization type.
    /// @param from        The payer (signer of the authorization).
    /// @param to          The payee (recipient of the transfer).
    /// @param value       The amount to transfer.
    /// @param validAfter  The earliest unix timestamp at which the authorization is valid.
    /// @param validBefore The latest unix timestamp at which the authorization is valid.
    /// @param nonce       A unique random 32-byte nonce.
    /// @param signature   Packed signature over the EIP-712 authorization struct.
    function _transferWithAuthorization(
        bytes32 typehash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes memory signature
    ) private {
        uint256 timestamp = block.timestamp;

        // Authorizations must be used after `validAfter`
        if (timestamp <= validAfter) revert AuthorizationNotYetValid({validAfter: validAfter});

        // Authorizations must be used before `validBefore`
        if (timestamp >= validBefore) revert AuthorizationExpired({validBefore: validBefore});

        // Validate authorization signature and nonce
        bytes32 structHash = keccak256(abi.encode(typehash, from, to, value, validAfter, validBefore, nonce));
        _consumeAuthorization({authorizer: from, nonce: nonce, structHash: structHash, signature: signature});
        emit AuthorizationUsed({authorizer: from, nonce: nonce});

        // Transfer tokens
        _transfer(from, to, value);
    }

    /// @notice Validates the signature, checks the nonce is unused, and marks it as consumed.
    ///
    /// @param authorizer  The authorizer address.
    /// @param nonce       The nonce to consume.
    /// @param structHash  The EIP-712 struct hash of the authorization.
    /// @param signature   The signature to validate against the authorizer.
    function _consumeAuthorization(address authorizer, bytes32 nonce, bytes32 structHash, bytes memory signature)
        private
    {
        ERC3009Layout storage $ = _getERC3009Layout();

        // Check authorization not yet consumed
        if ($.authorizationState[authorizer][nonce]) {
            revert AuthorizationAlreadyUsed({authorizer: authorizer, nonce: nonce});
        }

        // Validate signature over authorization
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(authorizer, digest, signature)) revert InvalidAuthorization();

        // Mark authorization as consumed
        $.authorizationState[authorizer][nonce] = true;
    }

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getERC3009Layout() private pure returns (ERC3009Layout storage $) {
        assembly {
            $.slot := _ERC3009_STORAGE_LOCATION
        }
    }
}
