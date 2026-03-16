// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MintAllowance
/// @author Coinbase
/// @notice ERC-7201 namespaced storage and logic for rate-limited mint allowances.
///
/// @dev Each minter has a maximum allowance that replenishes linearly over a
/// configurable interval. Minting deducts from the current allowance;
/// once depleted the minter must wait for it to refill.
abstract contract MintAllowance {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                ERC-7201 NAMESPACED STORAGE                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Configuration for a single minter's rate-limited allowance.
    struct MinterConfig {
        /// @dev The maximum allowance the minter can accumulate.
        uint256 maxAllowance;
        /// @dev The current available allowance.
        uint256 allowance;
        /// @dev The replenishment interval in seconds. Packed with `lastReplenished`.
        uint40 interval;
        /// @dev The unix timestamp (seconds) of the last replenishment. Packed with `interval`.
        uint40 lastReplenished;
    }

    /// @notice Storage layout for mint allowances.
    /// @custom:storage-location erc7201:coinbase.storage.CustomStablecoin.MintAllowance
    struct MintAllowanceLayout {
        /// @dev Maps each minter address to its rate-limit configuration.
        mapping(address minter => MinterConfig config) minters;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.CustomStablecoin.MintAllowance")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MINT_ALLOWANCE_STORAGE_LOCATION =
        0x32a75239f6b2b5cfaaa5a083b38ae38049a46ac226ace8c1f2cd933deef68500;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EVENTS / ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a minter's configuration is set or updated.
    ///
    /// @param minter        The minter address.
    /// @param maxAllowance  The new maximum allowance.
    /// @param interval      The new replenishment interval in seconds.
    event MinterConfigured(address indexed minter, uint256 maxAllowance, uint256 interval);

    /// @notice Emitted when a minter is removed.
    ///
    /// @param minter The minter address that was removed.
    event MinterRemoved(address indexed minter);

    /// @notice Emitted when a minter's allowance is replenished.
    ///
    /// @param minter            The minter address.
    /// @param allowance         The allowance after replenishment.
    /// @param amountReplenished The amount added during replenishment.
    event AllowanceReplenished(address indexed minter, uint256 allowance, uint256 amountReplenished);

    /// @notice Emitted when a minter's allowance is consumed by a mint.
    ///
    /// @param minter    The minter address.
    /// @param amount    The amount consumed.
    /// @param remaining The allowance remaining after consumption.
    event AllowanceConsumed(address indexed minter, uint256 amount, uint256 remaining);

    /// @notice Thrown when a mint would exceed the minter's current allowance.
    ///
    /// @param minter    The minter address.
    /// @param amount    The amount requested.
    /// @param allowance The available allowance at the time of the call.
    error MintAllowanceExceeded(address minter, uint256 amount, uint256 allowance);

    /// @notice Thrown when a minter configuration is invalid (zero maxAllowance or interval).
    error InvalidMinterConfig();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the estimated allowance for `minter` including pending replenishment.
    ///
    /// @param minter The minter address to query.
    ///
    /// @return Current allowance plus any amount that would be replenished at the current timestamp.
    function estimatedAllowance(address minter) public view virtual returns (uint256) {
        MinterConfig storage config = _getMintAllowanceLayout().minters[minter];
        return config.allowance + _replenishAmount(config);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets or replaces the rate-limit configuration for `minter`.
    ///
    /// @param minter       The minter address to configure.
    /// @param maxAllowance The maximum allowance the minter may accumulate.
    /// @param interval     The replenishment interval in seconds.
    function _configureMinter(address minter, uint256 maxAllowance, uint256 interval) internal {
        if (maxAllowance == 0 || interval == 0) revert InvalidMinterConfig();
        _getMintAllowanceLayout().minters[minter] = MinterConfig({
            maxAllowance: maxAllowance,
            allowance: maxAllowance,
            interval: uint40(interval),
            lastReplenished: uint40(block.timestamp)
        });
        emit MinterConfigured({minter: minter, maxAllowance: maxAllowance, interval: interval});
    }

    /// @notice Removes `minter` and deletes its configuration.
    ///
    /// @param minter The minter address to remove.
    function _removeMinter(address minter) internal {
        delete _getMintAllowanceLayout().minters[minter];
        emit MinterRemoved({minter: minter});
    }

    /// @notice Deducts `amount` from `minter`'s allowance, replenishing first if eligible.
    ///
    /// @param minter The minter address.
    /// @param amount The amount to consume.
    function _consumeMintAllowance(address minter, uint256 amount) internal {
        _replenish(minter);
        MinterConfig storage config = _getMintAllowanceLayout().minters[minter];
        if (amount > config.allowance) {
            revert MintAllowanceExceeded({minter: minter, amount: amount, allowance: config.allowance});
        }
        config.allowance -= amount;
        emit AllowanceConsumed({minter: minter, amount: amount, remaining: config.allowance});
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PRIVATE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Replenishes `minter`'s allowance based on elapsed time, then updates `lastReplenished`.
    ///
    /// @param minter The minter address to replenish.
    function _replenish(address minter) private {
        MinterConfig storage config = _getMintAllowanceLayout().minters[minter];
        if (config.allowance == config.maxAllowance) {
            config.lastReplenished = uint40(block.timestamp);
            return;
        }
        uint256 amount = _replenishAmount(config);
        if (amount == 0) return;
        config.allowance += amount;
        config.lastReplenished = uint40(block.timestamp);
        emit AllowanceReplenished({minter: minter, allowance: config.allowance, amountReplenished: amount});
    }

    /// @notice Returns a storage pointer to the ERC-7201 namespaced layout struct.
    ///
    /// @return $ Storage pointer to the layout struct.
    function _getMintAllowanceLayout() private pure returns (MintAllowanceLayout storage $) {
        assembly {
            $.slot := MINT_ALLOWANCE_STORAGE_LOCATION
        }
    }

    /// @notice Calculates how much allowance would be added to `config` at the current timestamp.
    ///
    /// @param config Storage pointer to the minter's configuration.
    ///
    /// @return The amount that would be replenished, capped at the remaining headroom.
    function _replenishAmount(MinterConfig storage config) private view returns (uint256) {
        uint256 elapsed = block.timestamp - config.lastReplenished;
        uint256 amount = Math.mulDiv(elapsed, config.maxAllowance, config.interval);
        uint256 afterReplenish = config.allowance + amount;
        if (afterReplenish > config.maxAllowance) {
            amount = config.maxAllowance - config.allowance;
        }
        return amount;
    }
}
