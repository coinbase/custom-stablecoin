// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IB20} from "base-std/interfaces/IB20.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";

import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

import {StablecoinFactoryTest} from "test/lib/StablecoinFactoryTest.sol";

/// @dev End-to-end integration tests for the factory's B-20 issuance path.
contract StablecoinE2EB20Test is StablecoinFactoryTest {
    /// @notice Verifies multiple B-20 stablecoins issued from the factory are fully independent
    /// @dev Cross-contract isolation: wiring a policy on token A must have no effect on token B
    function test_e2e_multipleB20StablecoinsFromFactory(bytes32 salt1, bytes32 salt2) public {
        vm.assume(salt1 != salt2);

        // Issue two B-20 stablecoins through the factory
        address addrA = _deployB20(salt1);
        address addrB = _deployB20(salt2);
        assertNotEq(addrA, addrB);

        IB20 scA = IB20(addrA);
        IB20 scB = IB20(addrB);

        // Wire the transfer-sender policy on token A only
        vm.prank(stablecoinAdmin);
        scA.updatePolicy(B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID);

        // Token A reflects the new policy; token B is unaffected
        assertEq(scA.policyId(B20Constants.TRANSFER_SENDER_POLICY), PolicyRegistryConstants.ALWAYS_BLOCK_ID);
        assertEq(scB.policyId(B20Constants.TRANSFER_SENDER_POLICY), 0);
    }
}
