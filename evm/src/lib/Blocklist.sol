// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @title Blocklist
/// @author Coinbase
/// @notice ERC-7201 namespaced storage and logic for blocklisted addresses.
abstract contract Blocklist {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for the blocklist.
    /// @custom:storage-location erc7201:coinbase.storage.Stablecoin.Blocklist
    struct BlocklistLayout {
        /// @dev Maps each account address to its blocklist status.
        mapping(address account => bool isBlocklisted) blocklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.Stablecoin.Blocklist")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _BLOCKLIST_STORAGE_LOCATION =
        0x2b7d78bb522e987c413d13def90590415d174dbd956b1e8f62074dd049e4d100;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an account's blocklist status is updated.
    ///
    /// @param account     The address whose status changed.
    /// @param blocklisted The new blocklist status.
    event BlocklistStatusUpdated(address indexed account, bool blocklisted);

    /// @notice Thrown when the blocklist status is already set to the requested value.
    ///
    /// @param account     The address.
    /// @param blocklisted The current (unchanged) status.
    error BlocklistStatusUnchanged(address account, bool blocklisted);

    /// @notice Thrown when a blocklisted address attempts a restricted action.
    ///
    /// @param account The blocklisted address.
    error AddressBlocklisted(address account);

    /// @notice Thrown when attempting to blocklist the zero address.
    error CannotBlocklistZeroAddress();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns whether `account` is blocklisted.
    ///
    /// @param account The address to query.
    ///
    /// @return True if the address is blocklisted.
    function isBlocklisted(address account) public view virtual returns (bool) {
        return _getBlocklistLayout().blocklisted[account];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Updates the blocklist status for `account`.
    ///
    /// @param account     The address to update.
    /// @param blocklisted Whether the account should be blocklisted.
    function _updateBlocklistStatus(address account, bool blocklisted) internal {
        if (blocklisted && account == address(0)) revert CannotBlocklistZeroAddress();
        if (isBlocklisted(account) == blocklisted) {
            revert BlocklistStatusUnchanged({account: account, blocklisted: blocklisted});
        }
        _getBlocklistLayout().blocklisted[account] = blocklisted;
        emit BlocklistStatusUpdated({account: account, blocklisted: blocklisted});
    }

    /// @notice Reverts if `account` is blocklisted.
    ///
    /// @param account The address to check.
    function _requireNotBlocklisted(address account) internal view {
        if (isBlocklisted(account)) revert AddressBlocklisted({account: account});
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getBlocklistLayout() private pure returns (BlocklistLayout storage $) {
        assembly {
            $.slot := _BLOCKLIST_STORAGE_LOCATION
        }
    }
}
