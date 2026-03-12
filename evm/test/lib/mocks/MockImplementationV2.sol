// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/// @dev Minimal implementation v2. Returns version 2 to distinguish from MockImplementation in delegation tests.
contract MockImplementationV2 {
    function version() external pure returns (uint256) {
        return 2;
    }
}
