// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

/// @dev Stub used in upgrade tests to simulate a recompiled, version-bumped Stablecoin
/// implementation. Not a subclass — intentionally standalone to mirror how a real upgrade
/// would work: a fresh compile with a bumped VERSION produces a new contract address.
contract StablecoinV2 {
    string public constant VERSION = "2.0.0";
}
