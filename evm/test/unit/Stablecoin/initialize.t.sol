// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {MutableBeaconProxy} from "src/MutableBeaconProxy.sol";
import {Stablecoin} from "src/Stablecoin.sol";
import {TokenMetadata} from "src/lib/TokenMetadata.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";
import {TwoStepUpgradeableBeacon} from "src/TwoStepUpgradeableBeacon.sol";

/// @dev Harness used only to reach the DecimalsAlreadyInitialized branch.
/// _initializeDecimals is onlyInitializing so it must be called from inside an initializer.
/// Calling it twice in one initializer hits the `$.decimals != 0` guard on the second call.
contract DecimalsHarness is TokenMetadata {
    function initDecimalsTwice(uint8 d) external initializer {
        _initializeDecimals(d);
        _initializeDecimals(d);
    }
}

contract StablecoinInitializeTest is StablecoinTest {
    /// @dev Deploy without initializing so each test can call initialize with controlled args.
    function setUp() public override {
        stablecoinImpl = new Stablecoin();
        beacon = new TwoStepUpgradeableBeacon(address(stablecoinImpl), admin);
        proxy = new MutableBeaconProxy(address(beacon), "");
        stablecoin = Stablecoin(address(proxy));

        vm.label(address(stablecoin), "Stablecoin");
        vm.label(address(stablecoinImpl), "Stablecoin(impl)");
        vm.label(address(beacon), "TwoStepUpgradeableBeacon");
        vm.label(admin, "admin");
    }

    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies initialize reverts when called on an already-initialized proxy
    /// @dev InvalidInitialization from OZ Initializable; the initializer modifier blocks re-entry
    function test_initialize_revert_alreadyInitialized() public {
        stablecoin.initialize(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, admin);

        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidInitialization()"))));
        stablecoin.initialize(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, admin);
    }

    /// @notice Verifies _initializeDecimals reverts when called a second time with decimals already set
    /// @dev DecimalsAlreadyInitialized: onlyInitializing allows two calls in one initializer;
    ///      the second call sees $.decimals != 0 and must revert. Tested via DecimalsHarness
    ///      because Stablecoin.initialize only calls _initializeDecimals once.
    function test_initialize_revert_decimalsAlreadyInitialized() public {
        DecimalsHarness harness = new DecimalsHarness();
        vm.expectRevert(TokenMetadata.DecimalsAlreadyInitialized.selector);
        harness.initDecimalsTwice(TOKEN_DECIMALS);
    }

    /// @notice Verifies initialize reverts when decimals is below the minimum of 6
    /// @dev DecimalsOutOfBounds: the valid range is [MIN_DECIMALS=6, MAX_DECIMALS=18] inclusive
    function test_initialize_revert_decimalsOutOfBounds_tooLow(uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 0, 5));
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("DecimalsOutOfBounds(uint8)")), decimals_));
        stablecoin.initialize(TOKEN_NAME, TOKEN_SYMBOL, decimals_, admin);
    }

    /// @notice Verifies initialize reverts when decimals is above the maximum of 18
    /// @dev DecimalsOutOfBounds: the valid range is [MIN_DECIMALS, MAX_DECIMALS] inclusive
    function test_initialize_revert_decimalsOutOfBounds_tooHigh(uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 19, 255));
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("DecimalsOutOfBounds(uint8)")), decimals_));
        stablecoin.initialize(TOKEN_NAME, TOKEN_SYMBOL, decimals_, admin);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies initialize sets the token name correctly
    /// @dev State: name() must equal the argument passed to initialize
    function test_initialize_success_setsName(string calldata name) public {
        stablecoin.initialize(name, TOKEN_SYMBOL, TOKEN_DECIMALS, admin);
        assertEq(stablecoin.name(), name);
    }

    /// @notice Verifies initialize sets the token symbol correctly
    /// @dev State: symbol() must equal the argument passed to initialize
    function test_initialize_success_setsSymbol(string calldata symbol) public {
        stablecoin.initialize(TOKEN_NAME, symbol, TOKEN_DECIMALS, admin);
        assertEq(stablecoin.symbol(), symbol);
    }

    /// @notice Verifies initialize sets the token decimals correctly for any valid value
    /// @dev State: decimals() must equal the argument; bounded to [MIN_DECIMALS=6, MAX_DECIMALS=18]
    function test_initialize_success_setsDecimals(uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 6, 18));
        stablecoin.initialize(TOKEN_NAME, TOKEN_SYMBOL, decimals_, admin);
        assertEq(stablecoin.decimals(), decimals_);
    }

    /// @notice Verifies initialize grants DEFAULT_ADMIN_ROLE to the provided admin address
    /// @dev Access control: only the specified admin should hold DEFAULT_ADMIN_ROLE after init
    function test_initialize_success_setsAdmin(address admin_) public {
        vm.assume(admin_ != address(0));
        stablecoin.initialize(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, admin_);
        assertTrue(stablecoin.hasRole(stablecoin.DEFAULT_ADMIN_ROLE(), admin_));
    }

    /// @notice Verifies the token starts unpaused after initialization
    /// @dev State: paused() must return false; transfers must be allowed immediately after init
    function test_initialize_success_startsUnpaused() public {
        stablecoin.initialize(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, admin);
        assertFalse(stablecoin.paused());
    }
}
