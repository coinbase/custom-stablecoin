// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MockBeacon} from "test/lib/mocks/MockBeacon.sol";
import {Stablecoin} from "src/Stablecoin.sol";
import {StablecoinFactory} from "src/StablecoinFactory.sol";

/// @dev Base test contract for StablecoinFactory. Deploys a UUPS-proxied factory backed by a
/// MockBeacon pointing at the Stablecoin implementation. All factory test files inherit from this.
contract StablecoinFactoryTest is Test {
    // ── Actors ───────────────────────────────────────────────────────────────────────────
    address internal admin = makeAddr("admin");
    address internal deployer = makeAddr("deployer");
    address internal stablecoinAdmin = makeAddr("stablecoinAdmin");
    address internal attacker = makeAddr("attacker");

    // ── Contracts ────────────────────────────────────────────────────────────────────────
    Stablecoin internal stablecoinImpl;
    MockBeacon internal beacon;
    StablecoinFactory internal factory;

    // ── Defaults ─────────────────────────────────────────────────────────────────────────
    string internal constant TOKEN_NAME = "Test USD";
    string internal constant TOKEN_SYMBOL = "TUSD";
    uint8 internal constant TOKEN_DECIMALS = 6;
    uint48 internal constant ADMIN_DELAY = 0;
    bytes32 internal constant DEPLOY_SALT = bytes32(uint256(1));

    // ── Setup ─────────────────────────────────────────────────────────────────────────────
    function setUp() public virtual {
        stablecoinImpl = new Stablecoin();
        beacon = new MockBeacon(address(stablecoinImpl));

        // Wrap factory in a UUPS proxy and initialize
        StablecoinFactory factoryImpl = new StablecoinFactory();
        bytes memory factoryInitData =
            abi.encodeCall(StablecoinFactory.initialize, (admin, ADMIN_DELAY, address(beacon), deployer));
        ERC1967Proxy factoryProxy = new ERC1967Proxy(address(factoryImpl), factoryInitData);
        factory = StablecoinFactory(address(factoryProxy));

        vm.label(address(stablecoinImpl), "Stablecoin(impl)");
        vm.label(address(beacon), "MockBeacon");
        vm.label(address(factory), "StablecoinFactory");
        vm.label(admin, "admin");
        vm.label(deployer, "deployer");
        vm.label(stablecoinAdmin, "stablecoinAdmin");
        vm.label(attacker, "attacker");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────────────────

    /// @dev Deploys a stablecoin via the factory with the given salt and default token params.
    function _deploy(bytes32 salt) internal returns (address) {
        vm.prank(deployer);
        return factory.deploy(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, stablecoinAdmin, salt);
    }

    /// @dev Deploys using the constant DEPLOY_SALT.
    function _deploy() internal returns (address) {
        return _deploy(DEPLOY_SALT);
    }

    /// @dev Computes the expected address for the default parameters and given salt.
    function _computeAddress(bytes32 salt) internal view returns (address) {
        return factory.computeAddress(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, stablecoinAdmin, salt);
    }
}
