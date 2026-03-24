// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

contract StorageLocationsTest is Test {
    function _erc7201Slot(string memory namespace) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(namespace))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_MintRateLimitStorageLocation() public pure {
        bytes32 expected = 0x7eb699b05d5796f4e90d066d564c9d07f2ed4e5efc8636ffae31415cc65f3a00;
        bytes32 computed = _erc7201Slot("coinbase.storage.Stablecoin.MintRateLimit");
        assertEq(computed, expected, "MintRateLimitStorage slot mismatch");
    }

    function test_BlocklistStorageLocation() public pure {
        bytes32 expected = 0x2b7d78bb522e987c413d13def90590415d174dbd956b1e8f62074dd049e4d100;
        bytes32 computed = _erc7201Slot("coinbase.storage.Stablecoin.Blocklist");
        assertEq(computed, expected, "BlocklistStorage slot mismatch");
    }

    function test_MetadataStorageLocation() public pure {
        bytes32 expected = 0xa3459737885856abeeb2a475f81a26ad8d8ccc56bd90faa293afd170849e1600;
        bytes32 computed = _erc7201Slot("coinbase.storage.Stablecoin.Metadata");
        assertEq(computed, expected, "MetadataStorage slot mismatch");
    }

    function test_ERC3009StorageLocation() public pure {
        bytes32 expected = 0xb8aebb83576e62291cd82363e38e83ae9b2360a49a089992dbdffe80b8e41600;
        bytes32 computed = _erc7201Slot("coinbase.storage.Stablecoin.ERC3009Upgradeable");
        assertEq(computed, expected, "ERC3009Storage slot mismatch");
    }
}
