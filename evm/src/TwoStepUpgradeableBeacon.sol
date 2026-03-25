// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @title TwoStepUpgradeableBeacon
/// @author Coinbase
/// @notice An {UpgradeableBeacon} whose ownership is transferred via a two-step process,
/// protecting against accidental ownership loss.
///
/// @dev Combines {UpgradeableBeacon} (implementation storage, validation, and {upgradeTo})
/// with {Ownable2Step} (propose + accept ownership transfer). Ownership does not change
/// until the pending owner explicitly calls {acceptOwnership}, preventing an erroneous
/// address from permanently locking beacon upgrades.
contract TwoStepUpgradeableBeacon is UpgradeableBeacon, Ownable2Step {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deploys the beacon pointing at `implementation_` with `owner_` as the initial owner.
    ///
    /// @param implementation_ The initial implementation contract. Must have deployed code.
    /// @param owner_          The initial owner who may call {upgradeTo} and {transferOwnership}.
    constructor(address implementation_, address owner_) UpgradeableBeacon(implementation_, owner_) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      PUBLIC FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Starts a two-step ownership transfer to `newOwner`.
    ///
    /// @dev Overrides both {Ownable.transferOwnership} and {Ownable2Step.transferOwnership}.
    /// The transfer is not complete until `newOwner` calls {acceptOwnership}.
    ///
    /// @param newOwner The address being proposed as the new owner.
    function transferOwnership(address newOwner) public override(Ownable, Ownable2Step) {
        Ownable2Step.transferOwnership(newOwner);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Completes an ownership transfer by storing the new owner.
    ///
    /// @dev Overrides both {Ownable._transferOwnership} and {Ownable2Step._transferOwnership}
    /// to ensure the two-step pending-owner state is cleared on completion.
    ///
    /// @param newOwner The address taking ownership.
    function _transferOwnership(address newOwner) internal override(Ownable, Ownable2Step) {
        Ownable2Step._transferOwnership(newOwner);
    }
}
