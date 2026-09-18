// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {RateLimit} from "src/lib/RateLimit.sol";
import {Stablecoin} from "src/Stablecoin.sol";
import {TwoStepUpgradeableBeacon} from "src/TwoStepUpgradeableBeacon.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Integration tests for multi-step admin workflows, permission choreography, and beacon
/// upgrade / exitBeacon scenarios. Extends StablecoinTest (fully configured stablecoin). Proxies
/// used by the beacon-upgrade scenarios are constructed directly over the shared beacon.
contract StablecoinWorkflowTest is StablecoinTest {
    address internal stablecoinAdmin = makeAddr("stablecoinAdmin");

    function setUp() public override {
        super.setUp();
        vm.label(stablecoinAdmin, "stablecoinAdmin");
    }

    // ── Admin setup workflows ─────────────────────────────────────────────────────────────

    /// @notice Verifies the complete admin setup sequence from proxy deploy to first mint
    /// @dev Integration: deploy → grantRole(MINT_ROLE) → configureMinter → mint; asserts state at each step
    function test_workflow_fullAdminSetup() public {
        // Step 1: Deploy a new stablecoin proxy
        address scAddr = _deployStablecoin(stablecoinAdmin);
        assertGt(scAddr.code.length, 0);

        Stablecoin sc = Stablecoin(scAddr);
        assertEq(sc.name(), TOKEN_NAME);
        assertEq(sc.decimals(), TOKEN_DECIMALS);

        // Step 2: Admin grants MINT_ROLE and MINT_RATE_LIMIT_ROLE
        vm.startPrank(stablecoinAdmin);
        sc.grantRole(sc.MINT_ROLE(), minter);
        sc.grantRole(sc.MINT_RATE_LIMIT_ROLE(), stablecoinAdmin);
        vm.stopPrank();
        assertTrue(sc.hasRole(sc.MINT_ROLE(), minter));

        // Step 3: Admin configures the minter's rate limit
        vm.prank(stablecoinAdmin);
        sc.configureMinter(minter, MINT_LIMIT, MINT_INTERVAL);
        assertEq(sc.currentMintLimit(minter), MINT_LIMIT);

        // Step 4: Minter mints tokens
        uint256 mintAmount = 1_000e6;
        vm.prank(minter);
        sc.mint(alice, mintAmount);
        assertEq(sc.balanceOf(alice), mintAmount);
        assertEq(sc.totalSupply(), mintAmount);
    }

    /// @notice Verifies the full minter lifecycle: grant → configure → mint → revoke clears config
    /// @dev Integration: revoking MINT_ROLE must zero out the minter's rate-limit and emit MinterRemoved
    function test_workflow_minterLifecycle(uint216 limit, uint40 interval) public {
        limit = uint216(bound(uint256(limit), 1, MINT_LIMIT));
        vm.assume(interval != 0);

        address minter2 = makeAddr("minter2");

        // Grant and configure
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), minter2);
        vm.stopPrank();
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minter2, limit, interval);
        assertEq(stablecoin.currentMintLimit(minter2), limit);

        // Mint something
        uint256 mintAmount = bound(limit, 1, limit);
        vm.prank(minter2);
        stablecoin.mint(carol, mintAmount);

        // Revoke MINT_ROLE — must emit MinterRemoved and clear config
        vm.expectEmit(true, true, false, false);
        emit RateLimit.RateLimitRemoved({key: stablecoin.MINT_RATE_LIMIT_KEY(), account: minter2});
        vm.startPrank(admin);
        stablecoin.revokeRole(stablecoin.MINT_ROLE(), minter2);
        vm.stopPrank();

        assertFalse(stablecoin.hasRole(stablecoin.MINT_ROLE(), minter2));
        // Config cleared: currentMintLimit reverts with RateLimitNotConfigured
        vm.expectRevert(
            abi.encodeWithSelector(RateLimit.RateLimitNotConfigured.selector, stablecoin.MINT_RATE_LIMIT_KEY(), minter2)
        );
        stablecoin.currentMintLimit(minter2);
    }

    // ── Pause / resume workflow ───────────────────────────────────────────────────────────

    /// @notice Verifies pause blocks transfers and unpause re-enables them, preserving balances throughout
    /// @dev State at each step: mint succeeds → pause → transfer reverts → unpause → transfer succeeds
    function test_workflow_pauseAndResume(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);

        // Mint to carol
        _mint(carol, amount);
        assertEq(stablecoin.balanceOf(carol), amount);

        // Pause
        _pause();
        assertTrue(stablecoin.paused());

        // Transfer blocked
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(carol);
        stablecoin.transfer(alice, 1);

        // Balances unchanged
        assertEq(stablecoin.balanceOf(carol), amount);

        // Unpause
        _unpause();
        assertFalse(stablecoin.paused());

        // Transfer succeeds
        vm.prank(carol);
        stablecoin.transfer(alice, amount);
        assertEq(stablecoin.balanceOf(carol), 0);
    }

    // ── Blocklist / unblocklist workflow ─────────────────────────────────────────────────

    /// @notice Verifies blocklisting blocks all transfer paths and unblocklisting restores them
    /// @dev State at each step: mint → blocklist → transfer blocked → unblocklist → transfer succeeds
    function test_workflow_blocklistAndUnblocklist(address account, uint256 amount) public {
        vm.assume(account != address(0) && account != minter);
        amount = bound(amount, 1, INITIAL_MINT);

        // Mint tokens to account
        uint256 balanceBefore = stablecoin.balanceOf(account);
        _mint(account, amount);
        assertEq(stablecoin.balanceOf(account), balanceBefore + amount);

        // Blocklist account
        _blocklist(account);
        assertTrue(stablecoin.isBlocklisted(account));

        // Inbound transfer blocked
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AddressBlocklisted(address)")), account));
        vm.prank(alice);
        stablecoin.transfer(account, 1);

        // Outbound transfer blocked
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AddressBlocklisted(address)")), account));
        vm.prank(account);
        stablecoin.transfer(alice, 1);

        // Unblocklist
        _unblocklist(account);
        assertFalse(stablecoin.isBlocklisted(account));

        // Transfer succeeds
        vm.prank(account);
        stablecoin.transfer(alice, 1);
        assertEq(stablecoin.balanceOf(account), balanceBefore + amount - 1);
    }

    // ── Beacon upgrade scenarios ──────────────────────────────────────────────────────────

    /// @notice Verifies that upgrading the beacon changes the implementation for all standard proxies
    /// @dev Beacon upgrade: deploy two proxies → upgrade beacon → both proxies delegate to new impl
    function test_workflow_beaconUpgradeAffectsAllProxies() public {
        // Deploy two stablecoin proxies over the shared beacon
        address proxyAddrA = _deployStablecoin(stablecoinAdmin);
        address proxyAddrB = _deployStablecoin(stablecoinAdmin);

        // Both proxies follow beacon (override slot is empty)
        assertEq(address(uint160(uint256(vm.load(proxyAddrA, ERC1967Utils.IMPLEMENTATION_SLOT)))), address(0));
        assertEq(address(uint160(uint256(vm.load(proxyAddrB, ERC1967Utils.IMPLEMENTATION_SLOT)))), address(0));
        assertEq(beacon.implementation(), address(stablecoinImpl));

        // Upgrade beacon to a new implementation (admin holds DEFAULT_ADMIN_ROLE on the beacon)
        Stablecoin newImpl = new Stablecoin();
        vm.prank(admin);
        beacon.upgradeTo(address(newImpl));
        assertEq(beacon.implementation(), address(newImpl));

        // Both proxies still have empty override slots (still following beacon)
        assertEq(address(uint160(uint256(vm.load(proxyAddrA, ERC1967Utils.IMPLEMENTATION_SLOT)))), address(0));
        assertEq(address(uint160(uint256(vm.load(proxyAddrB, ERC1967Utils.IMPLEMENTATION_SLOT)))), address(0));

        // Both proxies function correctly under new implementation
        assertEq(Stablecoin(proxyAddrA).name(), TOKEN_NAME);
        assertEq(Stablecoin(proxyAddrB).name(), TOKEN_NAME);
    }

    /// @notice Verifies that a proxy pointed at a new beacon is not affected by upgrades to the original beacon
    /// @dev upgradeBeaconToAndCall isolation: proxy A switches beacon → upgrade original beacon → proxy A unaffected; proxy B follows
    function test_workflow_updateBeaconDecouplesFromOriginalBeacon() public {
        address proxyAddrA = _deployStablecoin(stablecoinAdmin);
        address proxyAddrB = _deployStablecoin(stablecoinAdmin);

        // Proxy A switches to a separate beacon
        TwoStepUpgradeableBeacon beaconA = new TwoStepUpgradeableBeacon(address(stablecoinImpl), stablecoinAdmin);
        vm.prank(stablecoinAdmin);
        Stablecoin(proxyAddrA).upgradeBeaconToAndCall(address(beaconA), "");
        assertEq(address(uint160(uint256(vm.load(proxyAddrA, ERC1967Utils.BEACON_SLOT)))), address(beaconA));

        // Upgrade the original beacon to newImpl (admin holds DEFAULT_ADMIN_ROLE on the beacon)
        Stablecoin newImpl = new Stablecoin();
        vm.prank(admin);
        beacon.upgradeTo(address(newImpl));

        // Proxy A: beacon slot still points at beaconA (decoupled from original beacon)
        assertEq(address(uint160(uint256(vm.load(proxyAddrA, ERC1967Utils.BEACON_SLOT)))), address(beaconA));

        // Proxy B: beacon slot unchanged, still follows original beacon → newImpl
        assertEq(address(uint160(uint256(vm.load(proxyAddrB, ERC1967Utils.BEACON_SLOT)))), address(beacon));
        assertEq(beacon.implementation(), address(newImpl));

        // Both still function
        assertEq(Stablecoin(proxyAddrA).name(), TOKEN_NAME);
        assertEq(Stablecoin(proxyAddrB).name(), TOKEN_NAME);
    }

    /// @notice Verifies that upgradeBeaconToAndCall can be called multiple times to redirect to successive beacons
    /// @dev Re-redirect: admin can call upgradeBeaconToAndCall again to switch to another beacon
    function test_workflow_updateBeaconCanBeRedirected() public {
        address proxyAddr = _deployStablecoin(stablecoinAdmin);

        Stablecoin impl2 = new Stablecoin();

        // First redirect: point at beaconA (wrapping stablecoinImpl)
        TwoStepUpgradeableBeacon beaconA = new TwoStepUpgradeableBeacon(address(stablecoinImpl), stablecoinAdmin);
        vm.prank(stablecoinAdmin);
        Stablecoin(proxyAddr).upgradeBeaconToAndCall(address(beaconA), "");
        assertEq(address(uint160(uint256(vm.load(proxyAddr, ERC1967Utils.BEACON_SLOT)))), address(beaconA));

        // Second redirect: switch to beaconB (wrapping impl2)
        TwoStepUpgradeableBeacon beaconB = new TwoStepUpgradeableBeacon(address(impl2), stablecoinAdmin);
        vm.prank(stablecoinAdmin);
        Stablecoin(proxyAddr).upgradeBeaconToAndCall(address(beaconB), "");
        assertEq(address(uint160(uint256(vm.load(proxyAddr, ERC1967Utils.BEACON_SLOT)))), address(beaconB));

        // Proxy still functions
        assertEq(Stablecoin(proxyAddr).name(), TOKEN_NAME);
    }
}
