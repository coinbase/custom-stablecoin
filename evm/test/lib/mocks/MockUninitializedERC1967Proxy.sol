// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev An ERC1967Proxy that permits deployment without initialization data.
///      Used exclusively in tests that need to call initialize() separately from deployment.
contract MockUninitializedERC1967Proxy is ERC1967Proxy {
    constructor(address implementation) payable ERC1967Proxy(implementation, "") {}

    function _unsafeAllowUninitialized() internal pure override returns (bool) {
        return true;
    }
}
