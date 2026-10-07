// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
pragma abicoder v2;

import "./VerusObjects.sol";
import "../Storage/StorageMaster.sol";

/// @dev TEST ONLY. Stands in for the Imports slot: initialize() seeds one PENDING import record so the
///      real PendingImports vote / timeout paths can be driven, and executePendingImport is a no-op so
///      a released import completes. Never deploy to production.
contract MockSeedImport is VerusStorage {

    bytes32 constant PENDING_IMPORT_KEY_PREFIX = keccak256("pending.import");
    bytes32 public constant SEEDED_TXID = bytes32(uint256(0x5eed));

    function initialize() external {
        VerusObjects.pendingImport memory pending;
        pending.importTxid = SEEDED_TXID;
        pending.submittedAt = uint64(block.timestamp);
        pending.state = 1; // IMPORT_STATE_PENDING
        storageGlobal[keccak256(abi.encodePacked(PENDING_IMPORT_KEY_PREFIX, SEEDED_TXID))] = abi.encode(pending);
    }

    function executePendingImport(bytes32) external {}
}
