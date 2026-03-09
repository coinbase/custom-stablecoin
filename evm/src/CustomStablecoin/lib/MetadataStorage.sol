// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/**
 * @dev ERC-7201 namespaced storage and logic for custom stablecoin metadata.
 */
library MetadataStorage {
    /// @custom:storage-location erc7201:coinbase.storage.CustomStablecoinMetadata
    struct Layout {
        uint8 decimals;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.CustomStablecoinMetadata")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x66b53881ceb340348a909da20537ea4651a41d3894250a80ee92424afdb9d700;

    uint8 internal constant MAX_DECIMALS = 18;

    error DecimalsOutOfBounds(uint8 decimals);

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    function setDecimals(uint8 value) internal {
        if (value > MAX_DECIMALS) revert DecimalsOutOfBounds(value);
        layout().decimals = value;
    }

    function getDecimals() internal view returns (uint8) {
        return layout().decimals;
    }
}
