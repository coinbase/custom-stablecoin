// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @title BlacklistStorage
/// @author Coinbase
/// @notice ERC-7201 namespaced storage and logic for blacklisted addresses.
library BlacklistStorage {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for the blacklist.
    /// @custom:storage-location erc7201:coinbase.storage.BlacklistStorage
    struct Layout {
        /// @dev Maps each account address to its blacklist status.
        mapping(address account => bool isBlacklisted) blacklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.BlacklistStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x51ff35e700a147d742b5b05d2789db8c2672221577bfe847aed99424c3df4b00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an account is added to the blacklist.
    ///
    /// @param account The address that was blacklisted.
    event AccountBlacklisted(address indexed account);

    /// @notice Emitted when an account is removed from the blacklist.
    ///
    /// @param account The address that was unblacklisted.
    event AccountUnBlacklisted(address indexed account);

    /// @notice Thrown when attempting to act on an address that is already blacklisted.
    ///
    /// @param account The blacklisted address.
    error AddressBlacklisted(address account);

    /// @notice Thrown when attempting to unblacklist an address that is not blacklisted.
    ///
    /// @param account The address that is not blacklisted.
    error AddressNotBlacklisted(address account);

    /// @notice Thrown when attempting to blacklist the zero address.
    error CannotBlacklistZeroAddress();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Adds `account` to the blacklist.
    ///
    /// @param account The address to blacklist.
    function blacklist(address account) internal {
        if (account == address(0)) revert CannotBlacklistZeroAddress();
        if (isBlacklisted(account)) revert AddressBlacklisted({account: account});
        layout().blacklisted[account] = true;
        emit AccountBlacklisted({account: account});
    }

    /// @notice Removes `account` from the blacklist.
    ///
    /// @param account The address to unblacklist.
    function unBlacklist(address account) internal {
        if (!isBlacklisted(account)) revert AddressNotBlacklisted({account: account});
        layout().blacklisted[account] = false;
        emit AccountUnBlacklisted({account: account});
    }

    /// @notice Returns whether `account` is blacklisted.
    ///
    /// @param account The address to query.
    ///
    /// @return True if the address is blacklisted.
    function isBlacklisted(address account) internal view returns (bool) {
        return layout().blacklisted[account];
    }

    /// @notice Reverts if `account` is blacklisted.
    ///
    /// @param account The address to check.
    function requireNotBlacklisted(address account) internal view {
        if (isBlacklisted(account)) revert AddressBlacklisted({account: account});
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
