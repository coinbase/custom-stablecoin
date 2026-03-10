// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @title MetadataStorage
/// @author Coinbase
/// @notice ERC-7201 namespaced storage and logic for custom stablecoin metadata.
library MetadataStorage {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for token metadata.
    /// @custom:storage-location erc7201:coinbase.storage.CustomStablecoinMetadata
    struct Layout {
        /// @dev The number of decimals for the token.
        uint8 decimals;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.CustomStablecoinMetadata")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x66b53881ceb340348a909da20537ea4651a41d3894250a80ee92424afdb9d700;

    uint8 internal constant MAX_DECIMALS = 18;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when the provided decimals value exceeds `MAX_DECIMALS`.
    ///
    /// @param decimals The invalid decimals value provided.
    error DecimalsOutOfBounds(uint8 decimals);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the token's decimal places.
    ///
    /// @param value The number of decimals; must not exceed `MAX_DECIMALS`.
    function setDecimals(uint8 value) internal {
        if (value > MAX_DECIMALS) revert DecimalsOutOfBounds({decimals: value});
        layout().decimals = value;
    }

    /// @notice Returns the token's decimal places.
    ///
    /// @return The number of decimals.
    function getDecimals() internal view returns (uint8) {
        return layout().decimals;
    }

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function layout() internal pure returns (Layout storage $) {
        // Assembly is required to load from the ERC-7201 namespaced storage slot.
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
