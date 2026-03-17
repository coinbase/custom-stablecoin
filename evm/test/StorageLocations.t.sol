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

    function test_BlacklistStorageLocation() public pure {
        bytes32 expected = 0x9b498cdae840f81fb381d9b0d2886f7cc4fa4aea185af7bea0ce66283831de00;
        bytes32 computed = _erc7201Slot("coinbase.storage.Stablecoin.Blacklist");
        assertEq(computed, expected, "BlacklistStorage slot mismatch");
    }

    function test_MetadataStorageLocation() public pure {
        bytes32 expected = 0xa3459737885856abeeb2a475f81a26ad8d8ccc56bd90faa293afd170849e1600;
        bytes32 computed = _erc7201Slot("coinbase.storage.Stablecoin.Metadata");
        assertEq(computed, expected, "MetadataStorage slot mismatch");
    }

    function test_ERC3009StorageLocation() public pure {
        bytes32 expected = 0x427d307c31a45430da5a55d786be96204d2bd18e654f089714e3af8ce9abb000;
        bytes32 computed = _erc7201Slot("coinbase.storage.Stablecoin.ERC3009");
        assertEq(computed, expected, "ERC3009Storage slot mismatch");
    }

    function test_FactoryStorageLocation() public pure {
        bytes32 expected = 0x0359e5965fc60a4d7c47813a3cae31d4fea873da7c55a52a52894a5078215f00;
        bytes32 computed = _erc7201Slot("coinbase.storage.StablecoinFactory");
        assertEq(computed, expected, "FactoryStorage slot mismatch");
    }
}
