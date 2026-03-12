// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxyFactoryTest} from "test/lib/OverrideableBeaconProxyFactoryTest.sol";

contract OverrideableBeaconProxyFactoryGetAddressTest is OverrideableBeaconProxyFactoryTest {
    /// @notice Verifies getAddress returns the same address that deploy produces for the same arguments.
    /// @dev CREATE2 determinism: the pre-deployment prediction must match the actual deployed address exactly.
    function test_getAddress_success_matchesDeployedAddress(bytes32 salt, address proxyAdmin_) public {
        vm.assume(proxyAdmin_ != address(0));
        address predicted = factory.getAddress(salt, proxyAdmin_, "");
        address deployed = _deploy(salt, proxyAdmin_);
        assertEq(predicted, deployed);
    }

    /// @notice Verifies different salts produce different predicted addresses for the same admin.
    /// @dev Salt uniqueness: distinct salts must map to distinct addresses, preventing address collisions.
    function test_getAddress_success_differentSaltsGiveDifferentAddresses(address proxyAdmin_) public {
        vm.assume(proxyAdmin_ != address(0));
        bytes32 saltA = keccak256("saltA");
        bytes32 saltB = keccak256("saltB");
        address addrA = factory.getAddress(saltA, proxyAdmin_, "");
        address addrB = factory.getAddress(saltB, proxyAdmin_, "");
        assertTrue(addrA != addrB);
    }
}
