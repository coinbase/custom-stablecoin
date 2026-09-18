// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {IB20Stablecoin} from "base-std/interfaces/IB20Stablecoin.sol";

import {StablecoinFactory} from "src/StablecoinFactory.sol";

import {StablecoinFactoryTest} from "test/lib/StablecoinFactoryTest.sol";

/// @dev Unit tests for deployB20() and computeAddressB20(). computeAddressB20 tests are merged here
/// because the core invariant is that the computed address equals the issued token address.
contract StablecoinFactoryDeployB20Test is StablecoinFactoryTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies deployB20 reverts for any caller without DEPLOYER_ROLE
    /// @dev Access control: onlyRole(DEPLOYER_ROLE) must reject all unauthorized callers
    function test_deployB20_revert_unauthorized(address caller) public {
        vm.assume(caller != deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, factory.DEPLOYER_ROLE()
            )
        );
        vm.prank(caller);
        factory.deployB20(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin, DEPLOY_SALT);
    }

    /// @notice Verifies deployB20 reverts when the stablecoin admin is the zero address
    /// @dev Guard: an adminless B-20 would be permanently unconfigurable, matching the legacy path's rejection
    function test_deployB20_revert_zeroAdmin(bytes32 salt) public {
        vm.expectRevert(StablecoinFactory.StablecoinAdminRequired.selector);
        vm.prank(deployer);
        factory.deployB20(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, address(0), salt);
    }

    /// @notice Verifies deployB20 reverts when the same salt is used twice
    /// @dev Deterministic address collision: issuing to the same address twice must revert
    function test_deployB20_revert_saltReused(bytes32 salt) public {
        address predicted = _computeAddressB20(salt);
        _deployB20(salt);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.TokenAlreadyExists.selector, predicted));
        _deployB20(salt);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies deployB20 returns an address with contract code
    /// @dev State: the returned address must have code.length > 0 after issuance
    function test_deployB20_success_issuesToken(string calldata name, string calldata symbol) public {
        vm.prank(deployer);
        address token = factory.deployB20(name, symbol, TOKEN_CURRENCY, stablecoinAdmin, DEPLOY_SALT);
        assertGt(token.code.length, 0);
    }

    /// @notice Verifies deployB20 emits StablecoinDeployed with the correct parameters
    /// @dev Event integrity: all emitted fields must match the deploy arguments
    function test_deployB20_success_emitsStablecoinDeployed(bytes32 salt) public {
        address predicted = _computeAddressB20(salt);
        vm.expectEmit(true, true, true, true, address(factory));
        emit StablecoinFactory.StablecoinDeployed({
            stablecoin: predicted,
            name: TOKEN_NAME,
            symbol: TOKEN_SYMBOL,
            decimals: TOKEN_DECIMALS,
            stablecoinAdmin: stablecoinAdmin,
            salt: salt
        });
        _deployB20(salt);
    }

    /// @notice Verifies the issued token address matches the address returned by computeAddressB20
    /// @dev Determinism: the B-20 address must be predictable before issuance
    function test_deployB20_success_matchesComputedAddress(bytes32 salt) public {
        address predicted = _computeAddressB20(salt);
        address issued = _deployB20(salt);
        assertEq(issued, predicted);
    }

    /// @notice Verifies the issued token carries the requested name, symbol, and currency, and fixed 6 decimals
    /// @dev Integration: the STABLECOIN create params must be forwarded to the precompile correctly
    function test_deployB20_success_initializesStablecoin(string calldata name, string calldata symbol) public {
        vm.prank(deployer);
        address token = factory.deployB20(name, symbol, TOKEN_CURRENCY, stablecoinAdmin, DEPLOY_SALT);
        IB20Stablecoin sc = IB20Stablecoin(token);
        assertEq(sc.name(), name);
        assertEq(sc.symbol(), symbol);
        assertEq(sc.currency(), TOKEN_CURRENCY);
        assertEq(sc.decimals(), 6);
    }

    /// @notice Verifies the issued token grants DEFAULT_ADMIN_ROLE to the specified stablecoinAdmin
    /// @dev Integration: the initialAdmin create param must be wired through to a role grant
    function test_deployB20_success_setsStablecoinAdmin(address stablecoinAdmin_, bytes32 salt) public {
        vm.assume(stablecoinAdmin_ != address(0));
        vm.prank(deployer);
        address token = factory.deployB20(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin_, salt);
        IB20Stablecoin sc = IB20Stablecoin(token);
        assertTrue(sc.hasRole(sc.DEFAULT_ADMIN_ROLE(), stablecoinAdmin_));
    }

    // ── computeAddressB20 ─────────────────────────────────────────────────────────────────

    /// @notice Verifies computeAddressB20 returns different addresses for different salts
    /// @dev Determinism: distinct salts must produce distinct addresses
    function test_computeAddressB20_success_deterministicForDistinctSalts(bytes32 salt1, bytes32 salt2) public view {
        vm.assume(salt1 != salt2);
        assertNotEq(_computeAddressB20(salt1), _computeAddressB20(salt2));
    }

    /// @notice Verifies computeAddressB20 binds the address to every token configuration field
    /// @dev Address safety: changing any creation parameter while reusing a salt must change the predicted address
    function test_computeAddressB20_success_bindsTokenConfiguration(
        string calldata name,
        string calldata symbol,
        string calldata currency,
        address stablecoinAdmin_,
        bytes32 salt
    ) public view {
        vm.assume(keccak256(bytes(name)) != keccak256(bytes(TOKEN_NAME)));
        vm.assume(keccak256(bytes(symbol)) != keccak256(bytes(TOKEN_SYMBOL)));
        vm.assume(keccak256(bytes(currency)) != keccak256(bytes(TOKEN_CURRENCY)));
        vm.assume(stablecoinAdmin_ != stablecoinAdmin);

        address expected = _computeAddressB20(salt);
        assertNotEq(expected, factory.computeAddressB20(name, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin, salt));
        assertNotEq(expected, factory.computeAddressB20(TOKEN_NAME, symbol, TOKEN_CURRENCY, stablecoinAdmin, salt));
        assertNotEq(expected, factory.computeAddressB20(TOKEN_NAME, TOKEN_SYMBOL, currency, stablecoinAdmin, salt));
        assertNotEq(
            expected, factory.computeAddressB20(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin_, salt)
        );
    }

    /// @notice Verifies computeAddressB20 is stable before and after issuance
    /// @dev Idempotent: calling computeAddressB20 before and after deployB20() must return the same address
    function test_computeAddressB20_success_stableAcrossDeployment(bytes32 salt) public {
        address before = _computeAddressB20(salt);
        address issued = _deployB20(salt);
        address after_ = _computeAddressB20(salt);
        assertEq(before, issued);
        assertEq(before, after_);
    }
}
