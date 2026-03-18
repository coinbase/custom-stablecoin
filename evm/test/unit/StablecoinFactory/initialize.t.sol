// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StablecoinFactoryTest} from "test/lib/StablecoinFactoryTest.sol";
import {StablecoinFactory} from "src/StablecoinFactory.sol";

contract StablecoinFactoryInitializeTest is StablecoinFactoryTest {
    /// @dev Override setUp to deploy the factory impl without initializing.
    /// Each test calls initialize with controlled arguments.
    function setUp() public override {
        super.setUp();
        // factory from parent setUp is already initialized; tests here deploy their own fresh instance
    }

    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies initialize reverts when beacon_ is the zero address
    /// @dev BeaconNotSet: a zero beacon would permanently break all proxy deployments
    function test_initialize_revert_beaconNotSet(address admin_, address deployer_) public {
        StablecoinFactory freshImpl = new StablecoinFactory();
        bytes memory initData = abi.encodeCall(StablecoinFactory.initialize, (admin_, 0, address(0), deployer_));
        vm.expectRevert(StablecoinFactory.BeaconNotSet.selector);
        new ERC1967Proxy(address(freshImpl), initData);
    }

    /// @notice Verifies initialize reverts when called on an already-initialized factory
    /// @dev InvalidInitialization: the initializer modifier must prevent re-initialization
    function test_initialize_revert_alreadyInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidInitialization()"))));
        factory.initialize(admin, ADMIN_DELAY, address(beacon), deployer);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies initialize stores the beacon address and returns it via beacon()
    /// @dev State: beacon() must equal beacon_ after initialization; it is immutable thereafter
    function test_initialize_success_setsBeacon(address beacon_) public {
        vm.assume(beacon_ != address(0));
        StablecoinFactory freshImpl = new StablecoinFactory();
        bytes memory initData = abi.encodeCall(StablecoinFactory.initialize, (admin, 0, beacon_, deployer));
        StablecoinFactory freshFactory = StablecoinFactory(address(new ERC1967Proxy(address(freshImpl), initData)));
        assertEq(freshFactory.beacon(), beacon_);
    }

    /// @notice Verifies initialize grants DEPLOYER_ROLE to the deployer address
    /// @dev Access control: only the deployer should be able to call deploy() after initialization
    function test_initialize_success_grantsDeployerRole(address deployer_) public {
        StablecoinFactory freshImpl = new StablecoinFactory();
        bytes memory initData = abi.encodeCall(StablecoinFactory.initialize, (admin, 0, address(beacon), deployer_));
        StablecoinFactory freshFactory = StablecoinFactory(address(new ERC1967Proxy(address(freshImpl), initData)));
        assertTrue(freshFactory.hasRole(freshFactory.DEPLOYER_ROLE(), deployer_));
    }
}
