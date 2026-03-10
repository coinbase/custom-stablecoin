// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";

contract StorageLocationsTest is Test {
    function _erc7201Slot(string memory namespace) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(namespace))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_MintAllowanceStorageLocation() public pure {
        bytes32 expected = 0x8ad40bec58597f96feccbb9dfe34375a57195afd1bcc28b1b74fed4142680300;
        bytes32 computed = _erc7201Slot("coinbase.storage.MintAllowanceStorage");
        assertEq(computed, expected, "MintAllowanceStorage slot mismatch");
    }

    function test_BlacklistStorageLocation() public pure {
        bytes32 expected = 0x51ff35e700a147d742b5b05d2789db8c2672221577bfe847aed99424c3df4b00;
        bytes32 computed = _erc7201Slot("coinbase.storage.BlacklistStorage");
        assertEq(computed, expected, "BlacklistStorage slot mismatch");
    }

    function test_MetadataStorageLocation() public pure {
        bytes32 expected = 0x66b53881ceb340348a909da20537ea4651a41d3894250a80ee92424afdb9d700;
        bytes32 computed = _erc7201Slot("coinbase.storage.CustomStablecoinMetadata");
        assertEq(computed, expected, "MetadataStorage slot mismatch");
    }

    function test_FactoryStorageLocation() public pure {
        bytes32 expected = 0x2f479ea380745b703f8a394ca62a27f1007b7f21f9ec66b12e43f39167f1b900;
        bytes32 computed = _erc7201Slot("coinbase.storage.OverrideableBeaconProxyFactory");
        assertEq(computed, expected, "FactoryStorage slot mismatch");
    }

    function test_ProxyAdminStorageLocation() public pure {
        bytes32 expected = 0x48bf781b3e066d6328e65796599f6ef321293b13fff4a961d8e8d5252f809800;
        bytes32 computed = _erc7201Slot("coinbase.storage.OverrideableBeaconProxy");
        assertEq(computed, expected, "ProxyAdminStorage slot mismatch");
    }

    function test_UUPSProxyAdminStorageLocation() public pure {
        bytes32 expected = 0x670e8436571bca98ea80c6694fbb425064090a0f6338187a0c132d73b9d3c300;
        bytes32 computed = _erc7201Slot("coinbase.storage.UUPSOverrideableBeaconProxy");
        assertEq(computed, expected, "UUPSProxyAdminStorage slot mismatch");
    }
}
