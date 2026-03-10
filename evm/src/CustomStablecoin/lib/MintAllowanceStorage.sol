// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @dev ERC-7201 namespaced storage and logic for rate-limited mint allowances.
 *
 * Each minter has a maximum allowance that replenishes linearly over a
 * configurable interval. Minting deducts from the current allowance;
 * once depleted the minter must wait for it to refill.
 */
library MintAllowanceStorage {
    struct MinterConfig {
        uint256 maxAllowance;
        uint256 allowance;
        uint256 interval;
        uint256 lastReplenished;
    }

    /// @custom:storage-location erc7201:coinbase.storage.MintAllowanceStorage
    struct Layout {
        mapping(address => MinterConfig) minters;
    }

    // keccak256(abi.encode(uint256(keccak256("coinbase.storage.MintAllowanceStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x8ad40bec58597f96feccbb9dfe34375a57195afd1bcc28b1b74fed4142680300;

    event MinterConfigured(address indexed minter, uint256 maxAllowance, uint256 interval);
    event MinterRemoved(address indexed minter);
    event AllowanceReplenished(address indexed minter, uint256 allowance, uint256 amountReplenished);
    event AllowanceConsumed(address indexed minter, uint256 amount, uint256 remaining);

    error MintAllowanceExceeded(address minter, uint256 amount, uint256 allowance);
    error InvalidMinterConfig();

    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    function configureMinter(address minter, uint256 maxAllowance, uint256 interval) internal {
        if (maxAllowance == 0 || interval == 0) revert InvalidMinterConfig();
        layout().minters[minter] = MinterConfig({
            maxAllowance: maxAllowance,
            allowance: maxAllowance,
            interval: interval,
            lastReplenished: block.timestamp
        });
        emit MinterConfigured(minter, maxAllowance, interval);
    }

    function removeMinter(address minter) internal {
        delete layout().minters[minter];
        emit MinterRemoved(minter);
    }

    function consume(address minter, uint256 amount) internal {
        _replenish(minter);
        MinterConfig storage config = layout().minters[minter];
        if (amount > config.allowance) revert MintAllowanceExceeded(minter, amount, config.allowance);
        config.allowance -= amount;
        emit AllowanceConsumed(minter, amount, config.allowance);
    }

    function estimatedAllowance(address minter) internal view returns (uint256) {
        MinterConfig storage config = layout().minters[minter];
        return config.allowance + _replenishAmount(config);
    }

    function _replenish(address minter) private {
        MinterConfig storage config = layout().minters[minter];
        if (config.allowance == config.maxAllowance) {
            config.lastReplenished = block.timestamp;
            return;
        }
        uint256 amount = _replenishAmount(config);
        if (amount == 0) return;
        config.allowance += amount;
        config.lastReplenished = block.timestamp;
        emit AllowanceReplenished(minter, config.allowance, amount);
    }

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
