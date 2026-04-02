// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Stablecoin} from "src/Stablecoin.sol";
import {StablecoinFactory} from "src/StablecoinFactory.sol";

import {StablecoinFactoryTest} from "test/lib/StablecoinFactoryTest.sol";

/// @dev Unit tests for deploy() and computeAddress(). computeAddress tests are merged here
/// because the core invariant is that the computed address equals the deployed address.
contract StablecoinFactoryDeployTest is StablecoinFactoryTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies deploy reverts for any caller without DEPLOYER_ROLE
    /// @dev Access control: onlyRole(DEPLOYER_ROLE) must reject all unauthorized callers
    function test_deploy_revert_unauthorized(address caller) public {
        vm.assume(caller != deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, factory.DEPLOYER_ROLE()
            )
        );
        vm.prank(caller);
        factory.deploy(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, stablecoinAdmin, DEPLOY_SALT);
    }

    /// @notice Verifies deploy reverts when the same salt is used twice
    /// @dev CREATE2 collision: deploying to the same address twice must revert
    function test_deploy_revert_saltReused(bytes32 salt) public {
        _deploy(salt);
        vm.expectRevert();
        _deploy(salt);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies deploy returns an address with contract code
    /// @dev State: the returned address must have code.length > 0 after deployment
    function test_deploy_success_deploysProxy(string calldata name, string calldata symbol, uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 6, 18));
        vm.prank(deployer);
        address proxyAddr = factory.deploy(name, symbol, decimals_, stablecoinAdmin, DEPLOY_SALT);
        assertGt(proxyAddr.code.length, 0);
    }

    /// @notice Verifies deploy emits StablecoinDeployed with the correct parameters
    /// @dev Event integrity: all emitted fields must match the deploy arguments
    function test_deploy_success_emitsStablecoinDeployed(bytes32 salt) public {
        address predicted = _computeAddress(salt);
        vm.expectEmit(true, true, true, true);
        emit StablecoinFactory.StablecoinDeployed({
            stablecoin: predicted,
            name: TOKEN_NAME,
            symbol: TOKEN_SYMBOL,
            decimals: TOKEN_DECIMALS,
            stablecoinAdmin: stablecoinAdmin,
            salt: salt
        });
        _deploy(salt);
    }

    /// @notice Verifies the deployed proxy address matches the address returned by computeAddress
    /// @dev Determinism: CREATE2 address must be predictable before deployment
    function test_deploy_success_matchesComputedAddress(bytes32 salt) public {
        address predicted = _computeAddress(salt);
        address deployed = _deploy(salt);
        assertEq(deployed, predicted);
    }

    /// @notice Verifies the deployed proxy initializes the stablecoin with the correct name, symbol, and decimals
    /// @dev Integration: the initialize calldata in the proxy constructor must be forwarded correctly
    function test_deploy_success_initializesStablecoin(string calldata name, string calldata symbol, uint8 decimals_)
        public
    {
        decimals_ = uint8(bound(decimals_, 6, 18));
        vm.prank(deployer);
        address proxyAddr = factory.deploy(name, symbol, decimals_, stablecoinAdmin, DEPLOY_SALT);
        Stablecoin sc = Stablecoin(proxyAddr);
        assertEq(sc.name(), name);
        assertEq(sc.symbol(), symbol);
        assertEq(sc.decimals(), decimals_);
    }

    /// @notice Verifies the deployed proxy grants DEFAULT_ADMIN_ROLE to the specified stablecoinAdmin
    /// @dev Integration: the admin argument in initialize calldata must be wired through correctly
    function test_deploy_success_setsStablecoinAdmin(address stablecoinAdmin_, bytes32 salt) public {
        vm.assume(stablecoinAdmin_ != address(0));
        vm.prank(deployer);
        address proxyAddr = factory.deploy(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_DECIMALS, stablecoinAdmin_, salt);
        Stablecoin sc = Stablecoin(proxyAddr);
        assertTrue(sc.hasRole(sc.DEFAULT_ADMIN_ROLE(), stablecoinAdmin_));
    }

    // ── computeAddress ────────────────────────────────────────────────────────────────────

    /// @notice Verifies computeAddress returns different addresses for different salts
    /// @dev Determinism: distinct salts must produce distinct addresses for the same parameters
    function test_computeAddress_success_deterministicForDistinctSalts(bytes32 salt1, bytes32 salt2) public view {
        vm.assume(salt1 != salt2);
        address addr1 = _computeAddress(salt1);
        address addr2 = _computeAddress(salt2);
        assertNotEq(addr1, addr2);
    }

    /// @notice Verifies computeAddress is stable before and after deployment
    /// @dev Idempotent: calling computeAddress before and after deploy() must return the same address
    function test_computeAddress_success_stableAcrossDeployment(bytes32 salt) public {
        address before = _computeAddress(salt);
        address deployed = _deploy(salt);
        address after_ = _computeAddress(salt);
        assertEq(before, deployed);
        assertEq(before, after_);
    }
}
