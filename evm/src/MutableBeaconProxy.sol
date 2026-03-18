// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

/// @title MutableBeaconProxy
/// @author Coinbase
/// @notice A minimal {BeaconProxy} that supports a direct implementation
/// override via the ERC-1967 implementation slot, bypassing the beacon
/// for this proxy instance.
///
/// @dev Resolution order in {_implementation}:
///   1. If the ERC-1967 implementation slot is set, use it directly (opt-out).
///   2. Otherwise, query the beacon for the shared implementation (default).
///
/// The override is set from the implementation side (via delegatecall) rather
/// than through proxy-level admin functions, keeping the proxy minimal.
contract MutableBeaconProxy is BeaconProxy {
    /// @notice Deploys the proxy pointing at `beacon`.
    ///
    /// @param beacon The beacon contract supplying the shared implementation address.
    /// @param data   Optional calldata forwarded to the implementation via delegatecall on deployment.
    constructor(address beacon, bytes memory data) payable BeaconProxy(beacon, data) {}

    /// @notice Returns the beacon address.
    ///
    /// @dev Returns the address stored in the ERC-1967 beacon slot.
    ///
    /// @return The current beacon address.
    function _getBeacon() internal view override returns (address) {
        return ERC1967Utils.getBeacon();
    }
}
