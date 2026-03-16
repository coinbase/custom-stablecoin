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
    /// @custom:storage-location erc7201:coinbase.storage.CustomStablecoin.Metadata
    struct Layout {
        /// @dev The number of decimals for the token.
        uint8 decimals;
        /// @dev Whether decimals has been set (guards against re-initialization).
        bool decimalsSet;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.CustomStablecoin.Metadata")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0xeba5b3977d3b9de82516e2e616f881364b5bda38308f816dd84f2ec3c1947200;

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
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the token's decimal places (one-time only).
    ///
    /// @param value The number of decimals; must not exceed `MAX_DECIMALS`.
    function setDecimals(uint8 value) internal {
        Layout storage $ = layout();
        if ($.decimalsSet) revert DecimalsAlreadySet();
        if (value > MAX_DECIMALS) revert DecimalsOutOfBounds({decimals: value});
        $.decimals = value;
        $.decimalsSet = true;
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
