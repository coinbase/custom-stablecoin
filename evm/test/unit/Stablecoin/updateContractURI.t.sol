// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {TokenMetadata} from "src/lib/TokenMetadata.sol";
import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinUpdateContractURITest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies updateContractURI reverts for any caller without METADATA_ROLE
    /// @dev Access control: onlyRole(METADATA_ROLE) must reject all unauthorized callers
    function test_updateContractURI_revert_unauthorized(address caller) public {
        vm.assume(caller != metadataAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.METADATA_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.updateContractURI("ipfs://example");
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies updateContractURI stores the new URI and returns it via contractURI()
    /// @dev State: contractURI() must return newContractURI after a successful update
    function test_updateContractURI_success_setsURI(string calldata newURI) public {
        vm.prank(metadataAdmin);
        stablecoin.updateContractURI(newURI);
        assertEq(stablecoin.contractURI(), newURI);
    }

    /// @notice Verifies updateContractURI emits the ContractURIUpdated event
    /// @dev Event integrity: ERC-7572 requires this event to signal metadata consumers to refresh
    function test_updateContractURI_success_emitsContractURIUpdated(string calldata newURI) public {
        vm.expectEmit(false, false, false, false);
        emit TokenMetadata.ContractURIUpdated();
        vm.prank(metadataAdmin);
        stablecoin.updateContractURI(newURI);
    }
}
