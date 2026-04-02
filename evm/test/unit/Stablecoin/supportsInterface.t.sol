// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {StablecoinTest} from "test/lib/StablecoinTest.sol";

contract StablecoinSupportsInterfaceTest is StablecoinTest {
    /// @notice Verifies supportsInterface returns true for IERC20
    function test_supportsInterface_success_ierc20() public view {
        assertTrue(stablecoin.supportsInterface(type(IERC20).interfaceId));
    }

    /// @notice Verifies supportsInterface returns true for IERC20Permit (ERC-2612)
    function test_supportsInterface_success_ierc20Permit() public view {
        assertTrue(stablecoin.supportsInterface(type(IERC20Permit).interfaceId));
    }

    /// @notice Verifies supportsInterface returns true for IERC165 (inherited via AccessControl)
    function test_supportsInterface_success_ierc165() public view {
        assertTrue(stablecoin.supportsInterface(type(IERC165).interfaceId));
    }

    /// @notice Verifies supportsInterface returns true for IAccessControl (inherited via AccessControl)
    function test_supportsInterface_success_iAccessControl() public view {
        assertTrue(stablecoin.supportsInterface(type(IAccessControl).interfaceId));
    }

    /// @notice Verifies supportsInterface returns false for an unsupported interface
    function test_supportsInterface_success_returnsFalseForUnknown() public view {
        assertFalse(stablecoin.supportsInterface(0xdeadbeef));
    }
}
