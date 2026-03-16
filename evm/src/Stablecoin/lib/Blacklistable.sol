// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @title Blacklistable
/// @author Coinbase
/// @notice ERC-7201 namespaced storage and logic for blacklisted addresses.
abstract contract Blacklistable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for the blacklist.
    /// @custom:storage-location erc7201:coinbase.storage.CustomStablecoin.Blacklist
    struct BlacklistLayout {
        /// @dev Maps each account address to its blacklist status.
        mapping(address account => bool isBlacklisted) blacklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.CustomStablecoin.Blacklist")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BLACKLIST_STORAGE_LOCATION =
        0xaa42287b5df5a176a661599ae27fcd3a6641452f1e83e14656b2ec30bf606600;

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
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns whether `account` is blacklisted.
    ///
    /// @param account The address to query.
    ///
    /// @return True if the address is blacklisted.
    function isBlacklisted(address account) public view virtual returns (bool) {
        return _getBlacklistLayout().blacklisted[account];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Adds `account` to the blacklist.
    ///
    /// @param account The address to blacklist.
    function _blacklist(address account) internal {
        if (account == address(0)) revert CannotBlacklistZeroAddress();
        if (isBlacklisted(account)) revert AddressBlacklisted({account: account});
        _getBlacklistLayout().blacklisted[account] = true;
        emit AccountBlacklisted({account: account});
    }

    /// @notice Removes `account` from the blacklist.
    ///
    /// @param account The address to unblacklist.
    function _unBlacklist(address account) internal {
        if (!isBlacklisted(account)) revert AddressNotBlacklisted({account: account});
        _getBlacklistLayout().blacklisted[account] = false;
        emit AccountUnBlacklisted({account: account});
    }

    /// @notice Reverts if `account` is blacklisted.
    ///
    /// @param account The address to check.
    function _requireNotBlacklisted(address account) internal view {
        if (isBlacklisted(account)) revert AddressBlacklisted({account: account});
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getBlacklistLayout() private pure returns (BlacklistLayout storage $) {
        assembly {
            $.slot := BLACKLIST_STORAGE_LOCATION
        }
    }
}
