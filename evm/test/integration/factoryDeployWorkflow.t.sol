// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {OverrideableBeaconProxy} from "src/OverrideableBeaconProxy.sol";
import {OverrideableBeaconProxyFactoryTest} from "test/lib/OverrideableBeaconProxyFactoryTest.sol";

/// @dev Minimal interface for verifying which implementation the proxy delegates to.
interface IVersion {
    function version() external pure returns (uint256);
}

contract FactoryDeployWorkflowTest is OverrideableBeaconProxyFactoryTest {
    /// @notice Verifies a factory-deployed proxy is immediately usable with the correct admin and implementation.
    /// @dev E2E: proxy must have code, correct proxyAdmin, and delegate calls to the beacon's implementation.
    function test_integration_factoryDeploysUsableProxy() public {
        address proxyAddr = _deploy(bytes32(0), alice);

        assertGt(proxyAddr.code.length, 0);
        assertEq(OverrideableBeaconProxy(payable(proxyAddr)).proxyAdmin(), alice);
        assertEq(IVersion(proxyAddr).version(), 1);
    }

    /// @notice Verifies two proxies deployed with different salts are independent contracts at distinct addresses.
    /// @dev Isolation: each proxy has its own storage and the same admin actions on one do not affect the other.
    function test_integration_multipleSaltsGiveIndependentProxies(bytes32 salt1, bytes32 salt2) public {
        vm.assume(salt1 != salt2);

        address proxy1 = _deploy(salt1, alice);
        address proxy2 = _deploy(salt2, alice);

        assertTrue(proxy1 != proxy2);

        // Transferring admin on proxy1 does not affect proxy2.
        address nextAdmin = makeAddr("nextAdmin");
        vm.prank(alice);
        OverrideableBeaconProxy(payable(proxy1)).transferProxyAdmin(nextAdmin);
        assertEq(OverrideableBeaconProxy(payable(proxy1)).pendingProxyAdmin(), nextAdmin);
        assertEq(OverrideableBeaconProxy(payable(proxy2)).pendingProxyAdmin(), address(0));
    }

    /// @notice Verifies the address predicted by getAddress matches the address returned by deploy.
    /// @dev Determinism: CREATE2 pre-image is fully determined by beacon, admin, salt, and data.
    function test_integration_deterministicAddressMatchesPrecomputed(bytes32 salt, address proxyAdmin_) public {
        vm.assume(proxyAdmin_ != address(0));
        address predicted = factory.getAddress(salt, proxyAdmin_, "");
        address deployed = _deploy(salt, proxyAdmin_);
        assertEq(deployed, predicted);
    }
}
