// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/// @title Sanctionable
/// @author Coinbase
/// @notice ERC-7201 namespaced storage and logic for sanctioned addresses.
abstract contract Sanctionable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Storage layout for sanctions.
    /// @custom:storage-location erc7201:coinbase.storage.Stablecoin.Sanction
    struct SanctionLayout {
        /// @dev Maps each account address to its sanction status.
        mapping(address account => bool isSanctioned) sanctioned;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.Stablecoin.Sanction")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SANCTION_STORAGE_LOCATION =
        0x18554b1fc5de6153e5db6e86167c5329c7986180f7c380131540ec57c4270d00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an account's sanction status is updated.
    ///
    /// @param account    The address whose status changed.
    /// @param sanctioned The new sanction status.
    event SanctionStatusUpdated(address indexed account, bool sanctioned);

    /// @notice Thrown when the sanction status is already set to the requested value.
    ///
    /// @param account    The address.
    /// @param sanctioned The current (unchanged) status.
    error SanctionStatusUnchanged(address account, bool sanctioned);

    /// @notice Thrown when a sanctioned address attempts a restricted action.
    ///
    /// @param account The sanctioned address.
    error AddressSanctioned(address account);

    /// @notice Thrown when attempting to sanction the zero address.
    error CannotSanctionZeroAddress();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns whether `account` is sanctioned.
    ///
    /// @param account The address to query.
    ///
    /// @return True if the address is sanctioned.
    function isSanctioned(address account) public view virtual returns (bool) {
        return _getSanctionLayout().sanctioned[account];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Updates the sanction status for `account`.
    ///
    /// @param account    The address to update.
    /// @param sanctioned Whether the account should be sanctioned.
    function _updateSanctionStatus(address account, bool sanctioned) internal {
        if (sanctioned && account == address(0)) revert CannotSanctionZeroAddress();
        if (isSanctioned(account) == sanctioned) {
            revert SanctionStatusUnchanged({account: account, sanctioned: sanctioned});
        }
        _getSanctionLayout().sanctioned[account] = sanctioned;
        emit SanctionStatusUpdated({account: account, sanctioned: sanctioned});
    }

    /// @notice Reverts if `account` is sanctioned.
    ///
    /// @param account The address to check.
    function _requireNotSanctioned(address account) internal view {
        if (isSanctioned(account)) revert AddressSanctioned({account: account});
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getSanctionLayout() private pure returns (SanctionLayout storage $) {
        assembly {
            $.slot := SANCTION_STORAGE_LOCATION
        }
    }
}
