// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
pragma abicoder v2;

import "./VerusObjects.sol";
import "../Storage/StorageMaster.sol";

/// @dev TEST ONLY. Stands in for the Imports slot: initialize() seeds one PENDING import (record and queue entry) so the
///      real PendingImports vote / timeout paths can be driven, and executePendingImport is a no-op so
///      a released import completes. Never deploy to production.
contract MockSeedImport is VerusStorage {

    bytes32 constant PENDING_IMPORT_KEY_PREFIX = keccak256("pending.import");
    bytes32 constant PENDING_IMPORT_QUEUE_KEY = keccak256("pending.import.queue");
    bytes32 constant PENDING_IMPORT_QUEUE_INDEX_PREFIX = keccak256("pending.import.queue.index");
    bytes32 public constant SEEDED_TXID = bytes32(uint256(0x5eed));

    function initialize() external {
        VerusObjects.pendingImport memory pending;
        pending.importTxid = SEEDED_TXID;
        pending.submittedAt = uint64(block.timestamp);
        pending.state = 1; // IMPORT_STATE_PENDING
        storageGlobal[keccak256(abi.encodePacked(PENDING_IMPORT_KEY_PREFIX, SEEDED_TXID))] = abi.encode(pending);

        bytes32[] memory queue = new bytes32[](1);
        queue[0] = SEEDED_TXID;
        storageGlobal[PENDING_IMPORT_QUEUE_KEY] = abi.encode(queue);
        storageGlobal[keccak256(abi.encodePacked(PENDING_IMPORT_QUEUE_INDEX_PREFIX, SEEDED_TXID))] = abi.encode(uint256(0));
    }

    function executePendingImport(bytes32) external {}
}
