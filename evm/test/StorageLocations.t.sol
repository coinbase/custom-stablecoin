// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

contract StorageLocationsTest is Test {
    function _erc7201Slot(string memory namespace) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(namespace))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_MintAllowanceStorageLocation() public pure {
        bytes32 expected = 0x32a75239f6b2b5cfaaa5a083b38ae38049a46ac226ace8c1f2cd933deef68500;
        bytes32 computed = _erc7201Slot("coinbase.storage.CustomStablecoin.MintAllowance");
        assertEq(computed, expected, "MintAllowanceStorage slot mismatch");
    }

    function test_BlacklistStorageLocation() public pure {
        bytes32 expected = 0xaa42287b5df5a176a661599ae27fcd3a6641452f1e83e14656b2ec30bf606600;
        bytes32 computed = _erc7201Slot("coinbase.storage.CustomStablecoin.Blacklist");
        assertEq(computed, expected, "BlacklistStorage slot mismatch");
    }

    function test_MetadataStorageLocation() public pure {
        bytes32 expected = 0xeba5b3977d3b9de82516e2e616f881364b5bda38308f816dd84f2ec3c1947200;
        bytes32 computed = _erc7201Slot("coinbase.storage.CustomStablecoin.Metadata");
        assertEq(computed, expected, "MetadataStorage slot mismatch");
    }

    function test_FactoryStorageLocation() public pure {
        bytes32 expected = 0x2f479ea380745b703f8a394ca62a27f1007b7f21f9ec66b12e43f39167f1b900;
        bytes32 computed = _erc7201Slot("coinbase.storage.OverrideableBeaconProxyFactory");
        assertEq(computed, expected, "FactoryStorage slot mismatch");
    }

    function test_OverrideableBeaconProxyStorageLocation() public pure {
        bytes32 expected = 0x48bf781b3e066d6328e65796599f6ef321293b13fff4a961d8e8d5252f809800;
        bytes32 computed = _erc7201Slot("coinbase.storage.OverrideableBeaconProxy");
        assertEq(computed, expected, "OverrideableBeaconProxyStorage slot mismatch");
    }
}
