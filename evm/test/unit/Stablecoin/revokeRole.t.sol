// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {RateLimit} from "src/lib/RateLimit.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Tests for the _revokeRole override which clears the minter's rate-limit config
/// when MINT_ROLE is revoked. Other role revocations must not trigger this side effect.
contract StablecoinRevokeRoleTest is StablecoinTest {
    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies revoking MINT_ROLE clears the minter's rate-limit configuration
    /// @dev Side effect: _removeRateLimit is called; currentMintLimit reverts with RateLimitNotConfigured
    function test_revokeRole_success_clearsMinterConfig_whenMintRoleRevoked() public {
        vm.startPrank(admin);
        stablecoin.revokeRole(stablecoin.MINT_ROLE(), minter);
        vm.stopPrank();

        assertFalse(stablecoin.hasRole(stablecoin.MINT_ROLE(), minter));

        vm.expectRevert(
            abi.encodeWithSelector(RateLimit.RateLimitNotConfigured.selector, stablecoin.MINT_RATE_LIMIT_KEY(), minter)
        );
        stablecoin.currentMintLimit(minter);
    }

    /// @notice Verifies revoking MINT_ROLE emits RateLimitRemoved for the affected minter
    /// @dev Event integrity: RateLimitRemoved must be emitted to signal off-chain systems
    function test_revokeRole_success_emitsRateLimitRemoved_whenMintRoleRevoked() public {
        vm.expectEmit(true, true, false, false);
        emit RateLimit.RateLimitRemoved({key: stablecoin.MINT_RATE_LIMIT_KEY(), account: minter});
        vm.startPrank(admin);
        stablecoin.revokeRole(stablecoin.MINT_ROLE(), minter);
        vm.stopPrank();
    }

    /// @notice Verifies revoking any role other than MINT_ROLE does not clear any minter config
    /// @dev No side effect: _remove must only be called when role == MINT_ROLE
    function test_revokeRole_success_doesNotClearConfig_forOtherRoles(bytes32 role) public {
        vm.assume(role != stablecoin.MINT_ROLE());
        vm.assume(role != stablecoin.DEFAULT_ADMIN_ROLE());

        // Grant the fuzzed role to minter and then revoke it
        vm.prank(admin);
        stablecoin.grantRole(role, minter);
        vm.prank(admin);
        stablecoin.revokeRole(role, minter);

        // MINT_ROLE and rate-limit config must be unaffected
        assertTrue(stablecoin.hasRole(stablecoin.MINT_ROLE(), minter));
        uint256 limit = stablecoin.currentMintLimit(minter);
        assertLe(limit, MINT_LIMIT);
    }
}
