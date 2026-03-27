// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title TokenMetadata
/// @notice ERC-7201 namespaced storage and logic for custom stablecoin metadata.
/// @author Coinbase
abstract contract TokenMetadata is Initializable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for token metadata.
    /// @custom:storage-location erc7201:coinbase.storage.Stablecoin.Metadata
    struct MetadataLayout {
        /// @dev The number of decimals for the token (0 means unset).
        uint8 decimals;
        /// @dev The contract-level metadata URI (ERC-7572).
        string contractURI;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.Stablecoin.Metadata")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _METADATA_STORAGE_LOCATION =
        0xa3459737885856abeeb2a475f81a26ad8d8ccc56bd90faa293afd170849e1600;

    uint8 internal constant MIN_DECIMALS = 6;
    uint8 internal constant MAX_DECIMALS = 18;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when the contract-level metadata URI is updated (ERC-7572).
    event ContractURIUpdated();

    /// @notice Thrown when the provided decimals value is outside the range [`MIN_DECIMALS`, `MAX_DECIMALS`].
    ///
    /// @param decimals The invalid decimals value provided.
    error DecimalsOutOfBounds(uint8 decimals);

    /// @notice Thrown when decimals has already been set and cannot be changed.
    error DecimalsAlreadyInitialized();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the number of decimals used for token amounts.
    ///
    /// @return The number of decimals.
    function decimals() public view virtual returns (uint8) {
        return _getMetadataLayout().decimals;
    }

    /// @notice Returns the contract-level metadata URI (ERC-7572).
    ///
    /// @return The metadata URI string.
    function contractURI() public view virtual returns (string memory) {
        return _getMetadataLayout().contractURI;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the token's decimal places (one-time only).
    ///
    /// @param value The number of decimals; must be between `MIN_DECIMALS` and `MAX_DECIMALS` inclusive.
    function _initializeDecimals(uint8 value) internal onlyInitializing {
        MetadataLayout storage $ = _getMetadataLayout();
        if ($.decimals != 0) revert DecimalsAlreadyInitialized();
        if (value < MIN_DECIMALS || value > MAX_DECIMALS) revert DecimalsOutOfBounds({decimals: value});
        $.decimals = value;
    }

    /// @notice Sets the contract-level metadata URI (ERC-7572).
    ///
    /// @param newContractURI The new metadata URI.
    function _updateContractURI(string memory newContractURI) internal {
        _getMetadataLayout().contractURI = newContractURI;
        emit ContractURIUpdated();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getMetadataLayout() private pure returns (MetadataLayout storage $) {
        assembly {
            $.slot := _METADATA_STORAGE_LOCATION
        }
    }
}
