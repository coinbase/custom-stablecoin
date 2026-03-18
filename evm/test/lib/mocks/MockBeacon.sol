// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

/// @dev Minimal beacon mock. Stores the implementation address and allows
/// an owner-free upgrade for testing beacon-follow vs. exitBeacon scenarios.
contract MockBeacon is IBeacon {
    address private _implementation;

    constructor(address implementation_) {
        _implementation = implementation_;
    }

    /// @inheritdoc IBeacon
    function implementation() external view override returns (address) {
        return _implementation;
    }

    /// @dev Upgrades the beacon to a new implementation. No access control — tests only.
    function upgradeTo(address newImplementation) external {
        _implementation = newImplementation;
    }
}
