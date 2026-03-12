// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OverrideableBeaconProxyFactory} from "src/OverrideableBeaconProxyFactory.sol";
import {MockBeacon} from "test/lib/mocks/MockBeacon.sol";
import {MockImplementation} from "test/lib/mocks/MockImplementation.sol";
import {MockUninitializedERC1967Proxy} from "test/lib/mocks/MockUninitializedERC1967Proxy.sol";

contract OverrideableBeaconProxyFactoryTest is Test {
    // ── Actors ──────────────────────────────────────────────────
    address internal admin = makeAddr("admin");
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    // ── Constants ───────────────────────────────────────────────
    uint48 internal constant ADMIN_DELAY = 0;

    // ── Contracts ───────────────────────────────────────────────
    MockImplementation internal impl;
    MockBeacon internal beacon;
    OverrideableBeaconProxyFactory internal factory;

    // ── Setup ───────────────────────────────────────────────────

    function setUp() public virtual {
        impl = new MockImplementation();
        beacon = new MockBeacon(address(impl));

        OverrideableBeaconProxyFactory factoryImpl = new OverrideableBeaconProxyFactory();
        bytes memory initData =
            abi.encodeCall(OverrideableBeaconProxyFactory.initialize, (admin, ADMIN_DELAY, address(beacon)));
        factory = OverrideableBeaconProxyFactory(address(new ERC1967Proxy(address(factoryImpl), initData)));

        // Grant DEPLOYER_ROLE to a separate deployer actor in addition to admin.
        // Cache the role constant before pranking to avoid consuming the prank on the view call.
        bytes32 deployerRole = factory.DEPLOYER_ROLE();
        vm.prank(admin);
        factory.grantRole(deployerRole, deployer);

        vm.label(address(impl), "MockImplementation");
        vm.label(address(beacon), "MockBeacon");
        vm.label(address(factory), "OverrideableBeaconProxyFactory");
        vm.label(admin, "admin");
        vm.label(deployer, "deployer");
        vm.label(alice, "alice");
        vm.label(attacker, "attacker");
    }

    // ── Helpers ─────────────────────────────────────────────────

    /// @dev Deploys a proxy via the factory as the given caller with full control over parameters.
    function _deploy(address caller, bytes32 salt, address proxyAdmin_, bytes memory data) internal returns (address) {
        vm.prank(caller);
        return factory.deploy(salt, proxyAdmin_, data);
    }

    /// @dev Deploys a proxy via the factory as the admin with no init data (default caller).
    function _deploy(bytes32 salt, address proxyAdmin_) internal returns (address) {
        return _deploy(admin, salt, proxyAdmin_, "");
    }

    /// @dev Deploys a fresh uninitialized factory proxy. Used by initialize tests.
    ///      Uses MockUninitializedERC1967Proxy to bypass OZ 5.6's constructor-time
    ///      initialization requirement so initialize() can be called separately.
    function _freshUninitialized() internal returns (OverrideableBeaconProxyFactory) {
        OverrideableBeaconProxyFactory factoryImpl = new OverrideableBeaconProxyFactory();
        return OverrideableBeaconProxyFactory(address(new MockUninitializedERC1967Proxy(address(factoryImpl))));
    }
}
