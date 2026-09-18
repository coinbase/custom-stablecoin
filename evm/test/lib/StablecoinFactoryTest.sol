// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BaseTest} from "base-std-test/lib/BaseTest.sol";

import {Stablecoin} from "src/Stablecoin.sol";
import {StablecoinFactory} from "src/StablecoinFactory.sol";
import {TwoStepUpgradeableBeacon} from "src/TwoStepUpgradeableBeacon.sol";

/// @dev Base test contract for StablecoinFactory. Extends base-std's {BaseTest} (which etches the
/// B-20 precompile mocks and activates the STABLECOIN feature) and additionally wires the legacy
/// beacon stack, so both the beacon-proxy path ({deploy}) and the B-20 path ({deployB20}) are
/// exercisable. All factory test files inherit from this.
///
/// The `admin` and `attacker` actors are inherited from {BaseTest}.
contract StablecoinFactoryTest is BaseTest {
    // ── Actors ───────────────────────────────────────────────────────────────────────────
    address internal deployer = makeAddr("deployer");
    address internal stablecoinAdmin = makeAddr("stablecoinAdmin");

    // ── Contracts ────────────────────────────────────────────────────────────────────────
    Stablecoin internal stablecoinImpl;
    TwoStepUpgradeableBeacon internal beacon;
    StablecoinFactory internal factory;

    // ── Defaults ─────────────────────────────────────────────────────────────────────────
    string internal constant TOKEN_NAME = "Test USD";
    string internal constant TOKEN_SYMBOL = "TUSD";
    string internal constant TOKEN_CURRENCY = "USD";
    uint8 internal constant TOKEN_DECIMALS = 6;
    uint48 internal constant ADMIN_DELAY = 0;
    bytes32 internal constant DEPLOY_SALT = bytes32(uint256(1));

    // ── Setup ─────────────────────────────────────────────────────────────────────────────
    function setUp() public virtual override {
        // Etches the B-20 precompile mocks and activates the STABLECOIN feature.
        super.setUp();

        // Legacy beacon stack backing the {deploy} path (delay=0 for tests; use 2 days in production).
        stablecoinImpl = new Stablecoin();
        beacon = new TwoStepUpgradeableBeacon(address(stablecoinImpl), admin);

        // Wrap the factory in a UUPS proxy and initialize.
        StablecoinFactory factoryImpl = new StablecoinFactory(address(beacon));
        bytes memory factoryInitData = abi.encodeCall(StablecoinFactory.initialize, (admin, ADMIN_DELAY, deployer));
        ERC1967Proxy factoryProxy = new ERC1967Proxy(address(factoryImpl), factoryInitData);
        factory = StablecoinFactory(address(factoryProxy));

        vm.label(address(stablecoinImpl), "Stablecoin(impl)");
        vm.label(address(beacon), "TwoStepUpgradeableBeacon");
        vm.label(address(factory), "StablecoinFactory");
        vm.label(deployer, "deployer");
        vm.label(stablecoinAdmin, "stablecoinAdmin");
    }

    // ── Legacy (beacon-proxy) helpers ─────────────────────────────────────────────────────

    /// @dev Deploys a legacy beacon-proxy stablecoin with the given salt and default token params.
    function _deploy(bytes32 salt) internal returns (address) {
        vm.prank(deployer);
        return factory.deploy(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, stablecoinAdmin, salt);
    }

    /// @dev Deploys a legacy beacon-proxy stablecoin using the constant DEPLOY_SALT.
    function _deploy() internal returns (address) {
        return _deploy(DEPLOY_SALT);
    }

    /// @dev Computes the expected legacy beacon-proxy address for the default params and given salt.
    function _computeAddress(bytes32 salt) internal view returns (address) {
        return factory.computeAddress(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, stablecoinAdmin, salt);
    }

    // ── B-20 helpers ──────────────────────────────────────────────────────────────────────

    /// @dev Issues a B-20 stablecoin with the given salt and default token parameters.
    function _deployB20(bytes32 salt) internal returns (address) {
        vm.prank(deployer);
        return factory.deployB20(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin, salt);
    }

    /// @dev Computes the expected B-20 address for the given salt.
    function _computeAddressB20(bytes32 salt) internal view returns (address) {
        return factory.computeAddressB20(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin, salt);
    }
}
