// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/// @dev Minimal implementation v1. Exposes version() to verify the active delegation target in tests.
contract MockImplementation {
    function version() external pure returns (uint256) {
        return 1;
    }
}
