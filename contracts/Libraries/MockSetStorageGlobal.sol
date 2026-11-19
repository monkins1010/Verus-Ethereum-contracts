// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "../Storage/StorageMaster.sol";

/// @dev TEST ONLY. Installed with Delegator.replacecontract, its initialize() writes one storageGlobal record:
///      storageGlobal[KEY] = abi.encode(VALUE). Used to stand in for a data record whose key collides with a function
///      name (what the audit's 2^32 selector search produces), without the search. Never deploy to production.
contract MockSetStorageGlobal is VerusStorage {

    bytes32 immutable KEY;
    uint256 immutable VALUE;

    constructor(bytes32 key, uint256 value) {
        KEY = key;
        VALUE = value;
    }

    function initialize() external {
        storageGlobal[KEY] = abi.encode(VALUE);
    }
}
