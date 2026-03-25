// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MintRateLimit
/// @notice ERC-7201 namespaced storage and logic for rate-limited minting.
///
/// @dev Each minter has a capacity that replenishes linearly over a
/// configurable interval. Minting deducts from the remaining capacity;
/// once depleted the minter must wait for it to refill.
/// @author Coinbase
abstract contract MintRateLimit {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Configuration for a single minter's rate limit.
    struct MinterConfig {
        /// @dev The maximum mint capacity the minter can accumulate.
        uint256 limit;
        /// @dev The current remaining mint capacity.
        uint256 remaining;
        /// @dev The replenishment interval in seconds. Packed with `lastConsumed`.
        uint40 interval;
        /// @dev The unix timestamp (seconds) used as the replenishment anchor; updated on every
        ///      consumption and initialised to the configuration time. Packed with `interval`.
        uint40 lastConsumed;
    }

    /// @notice Storage layout for mint rate limits.
    /// @custom:storage-location erc7201:coinbase.storage.Stablecoin.MintRateLimit
    struct MintRateLimitLayout {
        /// @dev Maps each minter address to its rate-limit configuration.
        mapping(address minter => MinterConfig config) minters;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.Stablecoin.MintRateLimit")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MINT_RATE_LIMIT_STORAGE_LOCATION =
        0x7eb699b05d5796f4e90d066d564c9d07f2ed4e5efc8636ffae31415cc65f3a00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a minter's configuration is set or updated.
    ///
    /// @param minter   The minter address.
    /// @param limit    The new maximum mint capacity.
    /// @param interval The new replenishment interval in seconds.
    event MinterConfigured(address indexed minter, uint256 limit, uint40 interval);

    /// @notice Emitted when a minter is removed.
    ///
    /// @param minter The minter address that was removed.
    event MinterRemoved(address indexed minter);

    /// @notice Emitted when a minter's capacity is replenished.
    ///
    /// @param minter    The minter address.
    /// @param amount    The amount added during replenishment.
    /// @param remaining The remaining capacity after replenishment.
    event MintLimitReplenished(address indexed minter, uint256 amount, uint256 remaining);

    /// @notice Emitted when a minter's capacity is consumed by a mint.
    ///
    /// @param minter    The minter address.
    /// @param amount    The amount consumed.
    /// @param remaining The capacity remaining after consumption.
    event MintLimitConsumed(address indexed minter, uint256 amount, uint256 remaining);

    /// @notice Thrown when a mint would exceed the minter's remaining capacity.
    ///
    /// @param minter    The minter address.
    /// @param amount    The amount requested.
    /// @param remaining The remaining capacity at the time of the call.
    error MintLimitExceeded(address minter, uint256 amount, uint256 remaining);

    /// @notice Thrown when a minter configuration is invalid (zero limit or interval).
    error InvalidMinterConfig();

    /// @notice Thrown when a minter attempts to mint without an active rate-limit configuration.
    ///
    /// @param minter The minter address that has no configuration.
    error MinterNotConfigured(address minter);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the current mint limit for `minter`.
    ///
    /// @param minter The minter address to query.
    ///
    /// @return The current mint limit for `minter`.
    function currentMintLimit(address minter) public view virtual returns (uint256) {
        MinterConfig storage config = _getMintRateLimitLayout().minters[minter];

        uint256 elapsed = block.timestamp - config.lastConsumed;
        // Restores a percentage of the limit based on the elapsed time and interval.
        // Example: limit = 100, interval = 2 hours, elapsed time = 1 hour then the amount = 50 (50% of the limit)
        uint256 replenishmentAmount = Math.mulDiv(elapsed, config.limit, config.interval);

        // Ensures the remaining capacity does not exceed the limit.
        return Math.min(config.remaining + replenishmentAmount, config.limit);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deducts `amount` from `minter`'s remaining capacity, replenishing first if eligible.
    ///
    /// @param minter The minter address.
    /// @param amount The amount to consume.
    function _consumeMintLimit(address minter, uint256 amount) internal {
        MinterConfig storage config = _getMintRateLimitLayout().minters[minter];

        if (config.interval == 0) revert MinterNotConfigured(minter);

        // Get the current mint limit at this moment.
        uint256 currentMintLimit_ = currentMintLimit(minter);
        if (amount > currentMintLimit_) {
            revert MintLimitExceeded({minter: minter, amount: amount, remaining: currentMintLimit_});
        }

        // If the current mint limit is greater than the remaining capacity, replenish the capacity.
        if (currentMintLimit_ > config.remaining) {
            uint256 replenished = currentMintLimit_ - config.remaining;
            config.remaining = currentMintLimit_;
            emit MintLimitReplenished({minter: minter, amount: replenished, remaining: config.remaining});
        }

        config.remaining -= amount;
        config.lastConsumed = uint40(block.timestamp);

        emit MintLimitConsumed({minter: minter, amount: amount, remaining: config.remaining});
    }

    /// @notice Sets or replaces the rate-limit configuration for `minter`.
    ///
    /// @param minter   The minter address to configure.
    /// @param limit    The maximum mint capacity the minter may accumulate.
    /// @param interval The replenishment interval in seconds.
    function _configureMinter(address minter, uint256 limit, uint40 interval) internal {
        if (limit == 0 || interval == 0) revert InvalidMinterConfig();
        _getMintRateLimitLayout().minters[minter] =
            MinterConfig({limit: limit, remaining: limit, interval: interval, lastConsumed: uint40(block.timestamp)});
        emit MinterConfigured({minter: minter, limit: limit, interval: interval});
    }

    /// @notice Removes `minter` and deletes its configuration.
    ///
    /// @param minter The minter address to remove.
    function _removeMinter(address minter) internal {
        delete _getMintRateLimitLayout().minters[minter];
        emit MinterRemoved({minter: minter});
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getMintRateLimitLayout() private pure returns (MintRateLimitLayout storage $) {
        assembly {
            $.slot := MINT_RATE_LIMIT_STORAGE_LOCATION
        }
    }
}
