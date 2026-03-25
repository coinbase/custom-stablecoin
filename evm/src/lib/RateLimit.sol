// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title RateLimit
/// @author Coinbase
/// @notice ERC-7201 namespaced storage and logic for key-scoped, account-level rate limiting.
///
/// @dev Each (key, account) pair has an independent capacity that replenishes linearly over a
/// configurable interval. Consuming deducts from the remaining capacity; once depleted the
/// account must wait for it to refill.
///
/// Multiple independent rate limits can coexist within one contract by passing distinct keys
/// (e.g. `keccak256("MINT_RATE_LIMIT")`). The outer map is keyed by feature; the inner map
/// is keyed by account.
abstract contract RateLimit {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Rate-limit configuration for a single (key, account) pair.
    struct RateLimitConfig {
        /// @dev The maximum capacity the account can accumulate under this key.
        uint216 limit;
        /// @dev The replenishment interval in seconds. Packed with `lastConsumed`.
        uint40 interval;
        /// @dev The current remaining capacity.
        uint216 remaining;
        /// @dev The unix timestamp (seconds) used as the replenishment anchor; updated on every
        ///      consumption and initialised to the configuration time. Packed with `interval`.
        uint40 lastConsumed;
    }

    /// @notice Storage layout for all rate limits.
    /// @custom:storage-location erc7201:coinbase.storage.Stablecoin.RateLimit
    struct RateLimitLayout {
        /// @dev Outer key is the feature identifier; inner key is the account address.
        mapping(bytes32 key => mapping(address account => RateLimitConfig config)) limits;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.Stablecoin.RateLimit")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _RATE_LIMIT_STORAGE_LOCATION =
        0x5a044ec14f9996e1c7b3feb4fcac64ff4b38fefa34bc32f7dfd1713c9c25dc00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an account's rate-limit configuration is set or updated.
    ///
    /// @param key      The feature key scoping this rate limit.
    /// @param account  The account address.
    /// @param limit    The new maximum capacity.
    /// @param interval The new replenishment interval in seconds.
    event RateLimitConfigured(bytes32 indexed key, address indexed account, uint256 limit, uint40 interval);

    /// @notice Emitted when an account's rate-limit configuration is removed.
    ///
    /// @param key     The feature key scoping this rate limit.
    /// @param account The account address that was removed.
    event RateLimitRemoved(bytes32 indexed key, address indexed account);

    /// @notice Emitted when an account's capacity is replenished.
    ///
    /// @param key       The feature key scoping this rate limit.
    /// @param account   The account address.
    /// @param amount    The amount added during replenishment.
    /// @param remaining The remaining capacity after replenishment.
    event LimitReplenished(bytes32 indexed key, address indexed account, uint256 amount, uint256 remaining);

    /// @notice Emitted when an account's capacity is consumed.
    ///
    /// @param key       The feature key scoping this rate limit.
    /// @param account   The account address.
    /// @param amount    The amount consumed.
    /// @param remaining The capacity remaining after consumption.
    event LimitConsumed(bytes32 indexed key, address indexed account, uint256 amount, uint256 remaining);

    /// @notice Thrown when consumption would exceed the account's remaining capacity.
    ///
    /// @param key       The feature key scoping this rate limit.
    /// @param account   The account address.
    /// @param amount    The amount requested.
    /// @param remaining The remaining capacity at the time of the call.
    error LimitExceeded(bytes32 key, address account, uint256 amount, uint256 remaining);

    /// @notice Thrown when a rate-limit configuration is invalid (zero limit or interval).
    error InvalidConfig();

    /// @notice Thrown when an account attempts to consume capacity without an active configuration.
    ///
    /// @param key     The feature key scoping this rate limit.
    /// @param account The account address that has no configuration.
    error NotConfigured(bytes32 key, address account);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the current available capacity for `account` under `key`.
    ///
    /// @param key     The feature key scoping this rate limit.
    /// @param account The account address to query.
    ///
    /// @return The current available capacity.
    function currentLimit(bytes32 key, address account) public view virtual returns (uint256) {
        RateLimitConfig storage config = _getRateLimitLayout().limits[key][account];

        uint256 elapsed = block.timestamp - config.lastConsumed;
        // Restores a percentage of the limit based on elapsed time and the interval.
        // Example: limit = 100, interval = 2 hours, elapsed = 1 hour → replenishment = 50 (50% of limit)
        uint256 replenishmentAmount = Math.mulDiv(elapsed, config.limit, config.interval);

        // Ensures the available capacity does not exceed the configured limit.
        return Math.min(config.remaining + replenishmentAmount, config.limit);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deducts `amount` from `account`'s capacity under `key`, replenishing first if eligible.
    ///
    /// @param key     The feature key scoping this rate limit.
    /// @param account The account address.
    /// @param amount  The amount to consume.
    function _consumeLimit(bytes32 key, address account, uint256 amount) internal {
        RateLimitConfig storage config = _getRateLimitLayout().limits[key][account];

        if (config.interval == 0) revert NotConfigured({key: key, account: account});

        // Get the current available capacity at this moment.
        uint256 currentLimit_ = currentLimit(key, account);
        if (amount > currentLimit_) {
            revert LimitExceeded({key: key, account: account, amount: amount, remaining: currentLimit_});
        }


        // Safe: amount <= currentLimit_ is enforced above, and currentLimit_ fits in uint192.
        config.remaining = uint216(currentLimit_ - amount);
        config.lastConsumed = uint40(block.timestamp);

        emit LimitConsumed({key: key, account: account, amount: amount, remaining: config.remaining});
    }

    /// @notice Sets or replaces the rate-limit configuration for `account` under `key`.
    ///
    /// @param key      The feature key scoping this rate limit.
    /// @param account  The account address to configure.
    /// @param limit    The maximum capacity the account may accumulate.
    /// @param interval The replenishment interval in seconds.
    function _configureRateLimit(bytes32 key, address account, uint216 limit, uint40 interval) internal {
        if (limit == 0 || interval == 0) revert InvalidConfig();
        _getRateLimitLayout().limits[key][account] = RateLimitConfig({
            limit: limit, remaining: limit, interval: interval, lastConsumed: uint40(block.timestamp)
        });
        emit RateLimitConfigured({key: key, account: account, limit: limit, interval: interval});
    }

    /// @notice Removes `account`'s rate-limit configuration under `key`.
    ///
    /// @param key     The feature key scoping this rate limit.
    /// @param account The account address to remove.
    function _removeRateLimit(bytes32 key, address account) internal {
        delete _getRateLimitLayout().limits[key][account];
        emit RateLimitRemoved({key: key, account: account});
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getRateLimitLayout() private pure returns (RateLimitLayout storage $) {
        assembly {
            $.slot := _RATE_LIMIT_STORAGE_LOCATION
        }
    }
}
