// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

/// @title OverrideableBeaconProxy
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
contract OverrideableBeaconProxy is BeaconProxy {
    /// @notice Deploys the proxy pointing at `beacon`.
    ///
    /// @param beacon The beacon contract supplying the shared implementation address.
    /// @param data   Optional calldata forwarded to the implementation via delegatecall on deployment.
    constructor(address beacon, bytes memory data) payable BeaconProxy(beacon, data) {}

    /// @notice Accepts ETH and delegates to the implementation via the fallback mechanism.
    receive() external payable {
        _fallback();
    }

    /// @notice Returns the active implementation address.
    ///
    /// @dev Returns the ERC-1967 implementation slot if set (opt-out override),
    /// otherwise falls back to querying the beacon.
    ///
    /// @return The implementation address to delegate calls to.
    function _implementation() internal view override returns (address) {
        address directImpl = ERC1967Utils.getImplementation();
        if (directImpl != address(0)) {
            return directImpl;
        }
        return IBeacon(_getBeacon()).implementation();
    }
}
