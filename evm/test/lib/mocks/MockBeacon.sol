// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

/// @dev Minimal IBeacon mock with a settable implementation address.
contract MockBeacon is IBeacon {
    address private _impl;

    constructor(address impl_) {
        _impl = impl_;
    }

    function implementation() external view returns (address) {
        return _impl;
    }

    function setImplementation(address impl_) external {
        _impl = impl_;
    }
}
