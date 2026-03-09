// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/**
 * @dev ERC-7201 namespaced storage and logic for blacklisted addresses.
 */
library BlacklistStorage {
    /// @custom:storage-location erc7201:coinbase.storage.BlacklistStorage
    struct Layout {
        mapping(address => bool) blacklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.BlacklistStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x51ff35e700a147d742b5b05d2789db8c2672221577bfe847aed99424c3df4b00;

    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);

    error AddressBlacklisted(address account);
    error CannotBlacklistZeroAddress();

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    function blacklist(address account) internal {
        if (account == address(0)) revert CannotBlacklistZeroAddress();
        layout().blacklisted[account] = true;
        emit Blacklisted(account);
    }

    function unBlacklist(address account) internal {
        layout().blacklisted[account] = false;
        emit UnBlacklisted(account);
    }

    function isBlacklisted(address account) internal view returns (bool) {
        return layout().blacklisted[account];
    }

    function requireNotBlacklisted(address account) internal view {
        if (layout().blacklisted[account]) revert AddressBlacklisted(account);
    }
}
