// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @title MutableBeaconProxy
/// @notice A {BeaconProxy} variant whose beacon address can be changed after
/// deployment.
///
/// @dev The standard {BeaconProxy} caches the beacon in an immutable variable
/// at construction time, making the beacon address permanently fixed. This
/// contract overrides {_getBeacon} to read the beacon from the ERC-1967 beacon
/// storage slot on every call instead. Because delegatecalls from the
/// implementation execute in this proxy's storage context, the implementation
/// can update the beacon slot (e.g. via {ERC1967Utils.upgradeBeaconToAndCall}),
/// allowing each proxy instance to migrate to a different beacon independently.
/// @author Coinbase
contract MutableBeaconProxy is BeaconProxy {
    /// @notice Deploys the proxy pointing at `beacon`.
    ///
    /// @param beacon The beacon contract supplying the shared implementation address.
    /// @param data   Optional calldata forwarded to the implementation via delegatecall on deployment.
    constructor(address beacon, bytes memory data) payable BeaconProxy(beacon, data) {}

    /// @notice Returns the beacon address stored in the ERC-1967 beacon slot.
    ///
    /// @dev Overrides the base {BeaconProxy._getBeacon}, which returns an
    /// immutable variable. Reading from storage allows the beacon to be updated
    /// post-deployment by the implementation via delegatecall.
    ///
    /// @return The current beacon address.
    function _getBeacon() internal view override returns (address) {
        return ERC1967Utils.getBeacon();
    }
}
