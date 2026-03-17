// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @title TokenMetadata
/// @author Coinbase
/// @notice ERC-7201 namespaced storage and logic for custom stablecoin metadata.
abstract contract TokenMetadata {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for token metadata.
    /// @custom:storage-location erc7201:coinbase.storage.Stablecoin.Metadata
    struct MetadataLayout {
        /// @dev The number of decimals for the token.
        uint8 decimals;
        /// @dev Whether decimals has been set (guards against re-initialization).
        bool decimalsSet;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.Stablecoin.Metadata")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant METADATA_STORAGE_LOCATION =
        0xa3459737885856abeeb2a475f81a26ad8d8ccc56bd90faa293afd170849e1600;

    uint8 internal constant MAX_DECIMALS = 18;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when the provided decimals value exceeds `MAX_DECIMALS`.
    ///
    /// @param decimals The invalid decimals value provided.
    error DecimalsOutOfBounds(uint8 decimals);

    /// @notice Thrown when decimals has already been set and cannot be changed.
    error DecimalsAlreadySet();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the number of decimals used for token amounts.
    ///
    /// @return The number of decimals.
    function decimals() public view virtual returns (uint8) {
        return _getMetadataLayout().decimals;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the token's decimal places (one-time only).
    ///
    /// @param value The number of decimals; must not exceed `MAX_DECIMALS`.
    function _setDecimals(uint8 value) internal {
        MetadataLayout storage $ = _getMetadataLayout();
        if ($.decimalsSet) revert DecimalsAlreadySet();
        if (value > MAX_DECIMALS) revert DecimalsOutOfBounds({decimals: value});
        $.decimals = value;
        $.decimalsSet = true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getMetadataLayout() private pure returns (MetadataLayout storage $) {
        assembly {
            $.slot := METADATA_STORAGE_LOCATION
        }
    }
}
