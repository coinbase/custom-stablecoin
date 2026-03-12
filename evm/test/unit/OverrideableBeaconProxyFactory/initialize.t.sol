// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {OverrideableBeaconProxyFactory} from "src/OverrideableBeaconProxyFactory.sol";
import {OverrideableBeaconProxyFactoryTest} from "test/lib/OverrideableBeaconProxyFactoryTest.sol";

contract OverrideableBeaconProxyFactoryInitializeTest is OverrideableBeaconProxyFactoryTest {
    /// @notice Verifies initialize reverts when beacon_ is the zero address.
    /// @dev BeaconNotSet() must fire before any role or storage setup; fuzz confirms for any admin and delay.
    function test_initialize_revert_beaconNotSet(address admin_, uint48 delay) public {
        OverrideableBeaconProxyFactory f = _freshUninitialized();
        vm.expectRevert(OverrideableBeaconProxyFactory.BeaconNotSet.selector);
        f.initialize(admin_, delay, address(0));
    }

    /// @notice Verifies initialize stores the beacon address in ERC-7201 factory storage.
    /// @dev beacon() must return exactly the address passed as beacon_; fuzz confirms for any valid inputs.
    function test_initialize_success_setsBeacon(address admin_, uint48 delay) public {
        vm.assume(admin_ != address(0));
        OverrideableBeaconProxyFactory f = _freshUninitialized();
        f.initialize(admin_, delay, address(beacon));
        assertEq(f.beacon(), address(beacon));
    }

    /// @notice Verifies initialize grants DEPLOYER_ROLE to the admin automatically.
    /// @dev The admin must be able to call deploy() immediately after initialization without a separate grant.
    function test_initialize_success_grantsDeployerRoleToAdmin(address admin_, uint48 delay) public {
        vm.assume(admin_ != address(0));
        OverrideableBeaconProxyFactory f = _freshUninitialized();
        f.initialize(admin_, delay, address(beacon));
        assertTrue(f.hasRole(f.DEPLOYER_ROLE(), admin_));
    }

    /// @notice Verifies initialize cannot be called a second time on the same proxy.
    /// @dev The initializer modifier must block re-initialization, protecting all stored state from overwrite.
    function test_initialize_revert_alreadyInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        factory.initialize(admin, ADMIN_DELAY, address(beacon));
    }
}
