// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Gas benchmarks for core Stablecoin operations. Run `forge snapshot` to update .gas-snapshot
/// at the repo root and commit the result. In CI run `forge snapshot --diff` to catch regressions.
/// Benchmarks use bounded fuzz inputs so the snapshot records μ (mean) and ~ (median) across runs.
contract StablecoinBenchmarkTest is StablecoinTest {
    // ── Isolated operation benchmarks ─────────────────────────────────────────────────────

    /// @notice Measures gas for a single mint call with a standard bounded amount
    /// @dev Isolated: no prior state beyond setUp; regression guard for the mint path
    function test_benchmark_mint(uint256 amount) public {
        amount = bound(amount, 1, stablecoin.currentMintLimit(minter));
        vm.prank(minter);
        stablecoin.mint(alice, amount);
    }

    /// @notice Measures gas for a single burn call when the burner has a sufficient balance
    /// @dev Isolated: one prior mint to establish balance; regression guard for the burn path
    function test_benchmark_burn(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.prank(burner);
        stablecoin.burn(amount);
    }

    /// @notice Measures gas for a direct ERC-20 transfer between two accounts
    /// @dev Isolated: alice → bob transfer; regression guard for the _update hook overhead
    function test_benchmark_transfer(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        vm.prank(alice);
        stablecoin.transfer(bob, amount);
    }

    /// @notice Measures gas for a transferWithAuthorization submitted by a relayer
    /// @dev Isolated: signature validation + nonce write + transfer; regression guard for the full auth path
    function test_benchmark_transferWithAuthorization(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(1));
        bytes memory sig = _signTransferAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.prank(relayer);
        stablecoin.transferWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Measures gas for a receiveWithAuthorization submitted by the payee
    /// @dev Isolated: includes payee check + signature validation + nonce write + transfer
    function test_benchmark_receiveWithAuthorization(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_MINT);
        bytes32 nonce = bytes32(uint256(1));
        bytes memory sig = _signReceiveAuth(ALICE_KEY, alice, bob, amount, 0, type(uint256).max, nonce);
        vm.prank(bob);
        stablecoin.receiveWithAuthorization(alice, bob, amount, 0, type(uint256).max, nonce, sig);
    }

    /// @notice Measures gas for an updateSanctionStatus call that sanctions a previously clean address
    /// @dev Isolated: single storage write; regression guard for the sanction path
    function test_benchmark_updateSanctionStatus() public {
        vm.prank(sanctioner);
        stablecoin.updateSanctionStatus(carol, true);
    }

    // ── First vs. subsequent operation ───────────────────────────────────────────────────

    /// @notice Measures and compares gas for the first mint (cold storage) vs. a subsequent mint (warm storage)
    /// @dev SSTORE cold vs warm: first write initializes storage slots and costs significantly more
    function test_benchmark_mint_firstVsSubsequent(uint256 amount) public {
        amount = bound(amount, 1, stablecoin.currentMintLimit(minter) / 2);

        // First mint to a fresh address (cold SSTORE)
        address freshRecipient = makeAddr("freshRecipient");
        vm.prank(minter);
        stablecoin.mint(freshRecipient, amount);

        // Second mint to the same address (warm SSTORE)
        vm.prank(minter);
        stablecoin.mint(freshRecipient, amount);
    }
}
