// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {MintRateLimit} from "src/lib/MintRateLimit.sol";
import {StablecoinTest} from "test/lib/StablecoinTest.sol";

/// @dev Tests for the _revokeRole override which clears the minter's rate-limit config
/// when MINT_ROLE is revoked. Other role revocations must not trigger this side effect.
contract StablecoinRevokeRoleTest is StablecoinTest {
    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies revoking MINT_ROLE clears the minter's rate-limit configuration
    /// @dev Side effect: _removeMinter is called; currentMintLimit(minter) panics after revocation (interval=0)
    function test_revokeRole_clearsMinterConfig_whenMintRoleRevoked() public {
        vm.startPrank(admin);
        stablecoin.revokeRole(stablecoin.MINT_ROLE(), minter);
        vm.stopPrank();

        assertFalse(stablecoin.hasRole(stablecoin.MINT_ROLE(), minter));

        // Config is zeroed: currentMintLimit now panics because interval=0 (div by zero)
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x4e487b71), uint256(18)));
        stablecoin.currentMintLimit(minter);
    }

    /// @notice Verifies revoking MINT_ROLE emits MinterRemoved for the affected minter
    /// @dev Event integrity: MinterRemoved must be emitted to signal off-chain systems
    function test_revokeRole_emitsMinterRemoved_whenMintRoleRevoked() public {
        vm.expectEmit(true, false, false, false);
        emit MintRateLimit.MinterRemoved(minter);
        vm.startPrank(admin);
        stablecoin.revokeRole(stablecoin.MINT_ROLE(), minter);
        vm.stopPrank();
    }

    /// @notice Verifies revoking any role other than MINT_ROLE does not clear any minter config
    /// @dev No side effect: _removeMinter must only be called when role == MINT_ROLE
    function test_revokeRole_doesNotClearConfig_forOtherRoles(bytes32 role) public {
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
