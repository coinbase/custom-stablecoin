// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Stablecoin} from "src/Stablecoin.sol";

/// @dev Minimal v2 implementation used in upgrade tests. Overrides VERSION so tests can
/// confirm that the proxy delegates to the new implementation after a beacon upgrade.
contract StablecoinV2 is Stablecoin {
    string public constant VERSION_V2 = "2.0.0";

    /// @inheritdoc Stablecoin
    function version() public pure override returns (string memory) {
        return VERSION_V2;
    }
}
