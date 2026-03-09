// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

/**
 * @dev A {BeaconProxy} that allows the owner to set a direct implementation
 * override (opt-out), bypassing the beacon entirely for this proxy instance.
 *
 * Resolution order in {_implementation}:
 *   1. If the ERC-1967 implementation slot is set, use it directly (opt-out).
 *   2. Otherwise, query the beacon for the shared implementation (default).
 *
 * This uses only standard ERC-1967 storage slots — no custom slots needed.
 */
contract OverrideableBeaconProxy is BeaconProxy, Ownable2Step {
    event ImplementationOverrideSet(address indexed implementation);

    error InvalidImplementation(address implementation);

    constructor(address beacon, address owner_, bytes memory data)
        payable
        BeaconProxy(beacon, data)
        Ownable(owner_)
    {}

    /**
     * @dev Sets a direct implementation for this proxy, opting out of the beacon.
     *      Pass `address(0)` to clear the override and revert to beacon behavior.
     */
    function setImplementationOverride(address implementation) external onlyOwner {
        if (implementation != address(0) && implementation.code.length == 0) {
            revert InvalidImplementation(implementation);
        }
        StorageSlot.getAddressSlot(ERC1967Utils.IMPLEMENTATION_SLOT).value = implementation;
        emit ImplementationOverrideSet(implementation);
    }

    /**
     * @dev Returns the current override, or `address(0)` if using the beacon.
     */
    function implementationOverride() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    function renounceOwnership() public pure override {
        revert OwnableUnauthorizedAccount(address(0));
    }

    receive() external payable {
        _fallback();
    }

    function _implementation() internal view override returns (address) {
        address directImpl = ERC1967Utils.getImplementation();
        if (directImpl != address(0)) {
            return directImpl;
        }
        return IBeacon(_getBeacon()).implementation();
    }
}
