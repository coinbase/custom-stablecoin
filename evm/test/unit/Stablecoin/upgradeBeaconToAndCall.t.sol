// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";

import {Stablecoin} from "src/Stablecoin.sol";

import {MockBeacon} from "test/lib/mocks/MockBeacon.sol";
import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinUpdateBeaconToAndCallTest is StablecoinTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies updateBeaconToAndCall reverts for any caller without DEFAULT_ADMIN_ROLE
    /// @dev Access control: onlyRole(DEFAULT_ADMIN_ROLE) must reject all unauthorized callers
    function test_updateBeaconToAndCall_revert_unauthorized(address caller) public {
        vm.assume(!stablecoin.hasRole(stablecoin.DEFAULT_ADMIN_ROLE(), caller));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, stablecoin.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        stablecoin.updateBeaconToAndCall(address(beacon), "");
    }

    /// @notice Verifies updateBeaconToAndCall reverts when newBeacon is the zero address
    /// @dev InvalidBeacon: zero address has no code; must be rejected before the slot write
    function test_updateBeaconToAndCall_revert_invalidBeacon_zero() public {
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidBeacon.selector, address(0)));
        vm.prank(admin);
        stablecoin.updateBeaconToAndCall(address(0), "");
    }

    /// @notice Verifies updateBeaconToAndCall reverts when newBeacon points to an address with no code
    /// @dev InvalidBeacon: code.length == 0 check prevents pointing at EOAs or empty addresses
    function test_updateBeaconToAndCall_revert_invalidBeacon_noCode(address newBeacon) public {
        vm.assume(newBeacon != address(0));
        vm.assume(newBeacon.code.length == 0);
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidBeacon.selector, newBeacon));
        vm.prank(admin);
        stablecoin.updateBeaconToAndCall(newBeacon, "");
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies updateBeaconToAndCall writes the beacon slot so the proxy follows the new beacon
    /// @dev After the call, the proxy delegates to the new beacon's implementation, not the old one
    function test_updateBeaconToAndCall_success_updatesBeaconSlot() public {
        Stablecoin newImpl = new Stablecoin();
        MockBeacon newBeacon = new MockBeacon(address(newImpl));

        vm.prank(admin);
        stablecoin.updateBeaconToAndCall(address(newBeacon), "");

        // The ERC-1967 beacon slot should now point at newBeacon
        bytes32 slotValue = vm.load(address(proxy), ERC1967Utils.BEACON_SLOT);
        address resolvedBeacon = address(uint160(uint256(slotValue)));
        assertEq(resolvedBeacon, address(newBeacon));

        // The beacon resolves to the expected implementation address
        assertEq(IBeacon(resolvedBeacon).implementation(), address(newImpl));

        // Proxy still functions correctly via the new beacon
        assertEq(stablecoin.name(), TOKEN_NAME);
    }

    /// @notice Verifies updateBeaconToAndCall emits the BeaconUpgraded event with the new beacon address
    /// @dev Event integrity: IERC1967.BeaconUpgraded must be emitted so indexers track the beacon swap
    function test_updateBeaconToAndCall_success_emitsBeaconUpgraded() public {
        Stablecoin newImpl = new Stablecoin();
        MockBeacon newBeacon = new MockBeacon(address(newImpl));

        vm.expectEmit(true, false, false, false);
        emit IERC1967.BeaconUpgraded(address(newBeacon));
        vm.prank(admin);
        stablecoin.updateBeaconToAndCall(address(newBeacon), "");
    }
}
