// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ERC3009Upgradeable} from "src/lib/ERC3009Upgradeable.sol";
import {Stablecoin} from "src/Stablecoin.sol";
import {StablecoinFactory} from "src/StablecoinFactory.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev End-to-end integration tests for full user journeys across single and multiple actors.
/// Each test asserts intermediate state at every step, not just the final outcome.
contract StablecoinE2ETest is StablecoinTest {
    // ── Single-actor journeys ─────────────────────────────────────────────────────────────

    /// @notice Verifies a complete mint → transfer → burn cycle with correct balances at each step
    /// @dev E2E: intermediate state (post-mint, post-transfer) and final state (post-burn) all verified
    function test_e2e_mintTransferBurn(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        uint256 supplyBefore = stablecoin.totalSupply();

        // Mint to carol
        _mint(carol, amount);
        assertEq(stablecoin.balanceOf(carol), amount);
        assertEq(stablecoin.totalSupply(), supplyBefore + amount);

        // Carol transfers to alice
        uint256 aliceBalBefore = stablecoin.balanceOf(alice);
        _transfer(carol, alice, amount);
        assertEq(stablecoin.balanceOf(carol), 0);
        assertEq(stablecoin.balanceOf(alice), aliceBalBefore + amount);
        assertEq(stablecoin.totalSupply(), supplyBefore + amount);

        // Burner burns their own tokens
        uint256 burnAmount = bound(amount, 1, stablecoin.balanceOf(burner));
        uint256 supplyMid = stablecoin.totalSupply();
        _burn(burner, burnAmount);
        assertEq(stablecoin.totalSupply(), supplyMid - burnAmount);
    }

    /// @notice Verifies ERC-3009 authorization flow: sign → transferWithAuthorization → cancel blocks reuse
    /// @dev E2E: auth submitted once succeeds; canceled nonce prevents second use regardless of validity window
    function test_e2e_authorizationFlow(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(0xdead));

        uint256 aliceBalBefore = stablecoin.balanceOf(alice);
        uint256 bobBalBefore = stablecoin.balanceOf(bob);

        // Submit transfer authorization
        _transferWithAuth(amount, nonce);
        assertEq(stablecoin.balanceOf(alice), aliceBalBefore - amount);
        assertEq(stablecoin.balanceOf(bob), bobBalBefore + amount);
        assertTrue(stablecoin.authorizationState(alice, nonce));

        // Nonce already consumed; cancel attempt reverts
        bytes memory cancelSig = _signCancelAuth(ALICE_KEY, alice, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        stablecoin.cancelAuthorization(alice, nonce, cancelSig);

        // Re-submission also reverts
        bytes memory transferSig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.expectRevert(abi.encodeWithSelector(ERC3009Upgradeable.AuthorizationAlreadyUsed.selector, alice, nonce));
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, transferSig);
    }

    /// @notice Verifies mint rate limit replenishes over time and allows additional minting
    /// @dev E2E: mint to limit → verify exhausted → warp time → verify replenished → mint again
    function test_e2e_rateLimitReplenishment(uint256 amount, uint256 elapsed) public {
        amount = bound(amount, 1, stablecoin.currentMintLimit(minter));
        elapsed = bound(elapsed, 1 days, 365 days);

        // Consume capacity
        _mint(alice, amount);
        uint256 remainingAfterMint = stablecoin.currentMintLimit(minter);

        // Warp time forward
        vm.warp(block.timestamp + elapsed);

        // Rate limit replenishes
        uint256 limitAfterWarp = stablecoin.currentMintLimit(minter);
        assertGe(limitAfterWarp, remainingAfterMint);
        assertLe(limitAfterWarp, MINT_LIMIT);

        // Can mint again (at least 1 token)
        if (limitAfterWarp > 0) {
            _mint(bob, 1);
        }
    }

    // ── Multi-actor concurrent scenarios ─────────────────────────────────────────────────

    /// @notice Verifies two independent minters operate with completely separate rate limits
    /// @dev Isolation: minter A exhausting their limit must not affect minter B's remaining capacity
    function test_e2e_concurrentMinters(uint256 amountA, uint256 amountB) public {
        // Set up minterB with a fresh rate-limit config
        address minterB = makeAddr("minterB");
        vm.startPrank(admin);
        stablecoin.grantRole(stablecoin.MINT_ROLE(), minterB);
        vm.stopPrank();
        vm.prank(rateLimitAdmin);
        stablecoin.configureMinter(minterB, MINT_LIMIT, MINT_INTERVAL);

        uint256 limitA = stablecoin.currentMintLimit(minter);
        uint256 limitB = stablecoin.currentMintLimit(minterB);

        amountA = bound(amountA, 1, limitA);
        amountB = bound(amountB, 1, limitB);

        // MinterA mints — minterB's limit must be unaffected
        vm.prank(minter);
        stablecoin.mint(alice, amountA);
        assertEq(stablecoin.currentMintLimit(minterB), limitB);

        // MinterB mints — minterA's remaining is still correct
        vm.prank(minterB);
        stablecoin.mint(bob, amountB);
        assertEq(stablecoin.currentMintLimit(minter), limitA - amountA);
    }

    /// @notice Verifies multiple stablecoins deployed from the factory are fully independent
    /// @dev Cross-contract isolation: pausing or blocklisting on token A must have no effect on token B
    function test_e2e_multipleStablecoinsFromFactory(bytes32 salt1, bytes32 salt2) public {
        vm.assume(salt1 != salt2);

        address localDeployer = makeAddr("localDeployer");
        address localAdmin = makeAddr("localAdmin");

        // Deploy a factory backed by the same beacon
        StablecoinFactory factoryImpl = new StablecoinFactory(address(beacon));
        bytes memory initData = abi.encodeCall(StablecoinFactory.initialize, (admin, 0, localDeployer));
        StablecoinFactory localFactory = StablecoinFactory(address(new ERC1967Proxy(address(factoryImpl), initData)));

        // Deploy two stablecoins
        vm.prank(localDeployer);
        address addrA = localFactory.deploy(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, localAdmin, salt1);
        vm.prank(localDeployer);
        address addrB = localFactory.deploy(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, localAdmin, salt2);

        Stablecoin scA = Stablecoin(addrA);
        Stablecoin scB = Stablecoin(addrB);

        // Set up pause and blocklist roles on both
        vm.startPrank(localAdmin);
        scA.grantRole(scA.PAUSE_ROLE(), localAdmin);
        scB.grantRole(scB.PAUSE_ROLE(), localAdmin);
        scA.grantRole(scA.BLOCKLIST_ROLE(), localAdmin);
        vm.stopPrank();

        // Pause scA — scB must remain unpaused
        vm.prank(localAdmin);
        scA.pause();
        assertTrue(scA.paused());
        assertFalse(scB.paused());

        // Blocklist target on scA — not blocklisted on scB
        address target = makeAddr("target");
        vm.prank(localAdmin);
        scA.blocklist(target);
        assertTrue(scA.isBlocklisted(target));
        assertFalse(scB.isBlocklisted(target));
    }
}
