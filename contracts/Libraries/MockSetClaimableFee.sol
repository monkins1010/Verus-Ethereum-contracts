// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "../Storage/StorageMaster.sol";

/// @dev TEST ONLY. Installed with Delegator.replacecontract, its initialize() writes one claimableFees entry:
///      claimableFees[KEY] = VALUE. Used to seed the reserves a notarization would record. Never deploy to production.
contract MockSetClaimableFee is VerusStorage {

    bytes32 immutable KEY;
    uint256 immutable VALUE;

    constructor(bytes32 key, uint256 value) {
        KEY = key;
        VALUE = value;
    }

    function initialize() external {
        claimableFees[KEY] = VALUE;
    }
}
