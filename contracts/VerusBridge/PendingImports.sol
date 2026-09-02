// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjects.sol";
import "../Storage/StorageMaster.sol";

contract PendingImports is VerusStorage {

    bytes32 constant SUBMIT_IMPORTS_REENTRANCY_GUARD = "submitimports.reentrancy.lock";
    bytes32 constant APPROVE_OR_REJECT_IMPORT_VDXF_KEY = keccak256("approveOrRejectAcceptedImport");
    // Routes superseded by APPROVE_OR_REJECT_IMPORT_VDXF_KEY; deleted by initialize() on upgrade.
    bytes32 constant LEGACY_RELEASE_IMPORT_VDXF_KEY = keccak256("releasePendingImport");
    bytes32 constant LEGACY_APPROVE_IMPORT_VDXF_KEY = keccak256("approveImport");
    bytes32 constant GET_PENDING_IMPORTS_VDXF_KEY = keccak256("getPendingImports");
    bytes32 constant GET_PENDING_IMPORT_COUNT_VDXF_KEY = keccak256("getPendingImportCount");
    bytes32 constant PENDING_IMPORTS_CONTRACT_INDEX_KEY = keccak256("PendingImports.contract.index");
    bytes32 constant PENDING_IMPORT_KEY_PREFIX = keccak256("pending.import");
    bytes32 constant PENDING_IMPORT_NONCE_COUNTER_KEY = keccak256("pending.import.nonce.counter");
    bytes32 constant PENDING_IMPORT_QUEUE_KEY = keccak256("pending.import.queue");
    bytes32 constant PENDING_IMPORT_QUEUE_INDEX_PREFIX = keccak256("pending.import.queue.index");
    bytes32 constant RELEASE_VOTE_BITMAP_PREFIX = keccak256("pending.import.release.vote.bitmap");
    bytes32 constant REJECT_VOTE_BITMAP_PREFIX = keccak256("pending.import.reject.vote.bitmap");
    bytes32 constant HALT_VOTE_BITMAP_KEY = keccak256("bridge.halt.vote.bitmap");
    // Mirror of the constants in TokenManager / Imports — kept here so _executeImport
    // can clean up orphaned exec-data keys without depending on executePendingImport running.
    bytes32 constant PENDING_EXEC_DATA_PREFIX   = keccak256("pending.exec.data");
    bytes32 constant PENDING_EXEC_PARAMS_PREFIX = keccak256("pending.exec.params");

    address immutable VETH;

    uint8 constant IMPORT_STATE_PENDING = 1;
    uint8 constant IMPORT_STATE_RELEASED = 2;
    uint8 constant IMPORT_STATE_REJECTED = 3;

    uint256 constant IMPORT_RELEASE_COOLDOWN = 1 hours;
    uint256 constant IMPORT_TIMEOUT = 4 hours;

    bytes32 constant BRIDGE_PAUSED_KEY = keccak256("bridge.import.paused");
    event PendingImportQueued(bytes32 indexed importTxid, uint32 indexed nout, uint128 cceHeightsAndIndex, uint64 nonce);
    event PendingImportReleased(bytes32 indexed importTxid, address indexed releaser);
    event PendingImportApproved(bytes32 indexed importTxid, address indexed notarizerID, uint256 approvalCount);
    event PendingImportRejectVote(bytes32 indexed importTxid, address indexed notarizerID, uint256 rejectionCount);
    event PendingImportRejected(bytes32 indexed importTxid);
    event BridgePaused();
    event HaltVoteSubmitted(address indexed notarizerID, bool voteToHalt, uint256 voteCount, bool bridgePaused);

    constructor(address veth) {
        VETH = veth;
    }

    /// @notice Run once per upgrade of this contract via delegatecall from Delegator.replacecontract()
    ///         (or the UpgradeManager upgrade loop). Re-points the notary vote route at this slot and
    ///         retires the split approve/release routes it replaced.
    ///         No-op on a first deployment, where UpgradeManager.initialize() does the registration
    ///         before the slot-index key exists.
    function initialize() external {
        bytes memory indexData = storageGlobal[PENDING_IMPORTS_CONTRACT_INDEX_KEY];
        if (indexData.length == 0) return;

        storageGlobal[APPROVE_OR_REJECT_IMPORT_VDXF_KEY] = indexData;
        delete storageGlobal[LEGACY_RELEASE_IMPORT_VDXF_KEY];
        delete storageGlobal[LEGACY_APPROVE_IMPORT_VDXF_KEY];
    }

    /// @notice Called by SubmitImports (via reentrancy guard) to place an incoming cross-chain
    ///         import into pending. Assigns a monotonic nonce and adds the entry to the pending queue.
    function queuePendingImport(
        bytes32 importTxid,
        uint32 nout,
        bytes32 confirmedNotarizationTxid,
        uint32 confirmedNotarizationN,
        uint128 cceHeightsAndIndex,
        VerusObjects.PackedSend[] calldata transfers,
        VerusObjects.PackedCurrencyLaunch[] calldata launchTxs,
        uint64 fees,
        uint176[3] calldata exporters
    ) external {

        require(storageGlobal[BRIDGE_PAUSED_KEY].length == 0);
        bytes32 pendingKey = _pendingImportKey(importTxid);
        require(storageGlobal[pendingKey].length == 0);

        uint64 nonce = _nextPendingImportNonce();

        storageGlobal[pendingKey] = abi.encode(
            VerusObjects.pendingImport({
                importTxid: importTxid,
                nout: nout,
                confirmedNotarizationTxid: confirmedNotarizationTxid,
                confirmedNotarizationN: confirmedNotarizationN,
                transfers: transfers,
                launchTxs: launchTxs,
                fees: fees,
                cceHeightsAndIndex: cceHeightsAndIndex,
                exporters: exporters,
                nonce: nonce,
                submittedAt: uint64(block.timestamp),
                state: IMPORT_STATE_PENDING
            })
        );

        _enqueuePendingImport(importTxid);

        emit PendingImportQueued(
            importTxid,
            nout,
            cceHeightsAndIndex,
            nonce
        );
    }

    // Brian Kerninghan's bit counting algorithm, O(number of set bits) instead of O(32).
    function _countSetBits32(uint32 value) private pure returns (uint256 count) {
        uint32 x = value;
        while (x != 0) {
            x &= (x - 1);
            count++;
        }
    }

    /// @notice VDXF dispatcher path — called via Delegator.setVerusData(data, "getPendingImportCount").
    ///         Returns abi.encode(count) so the result can be passed back through the generic bytes interface.
    function getPendingImportCount(bytes calldata) external view returns (bytes memory) {
        return abi.encode(_loadPendingQueue().length);
    }

    /// @notice VDXF dispatcher path — called via Delegator.setVerusData(data, "getPendingImports").
    ///         Expects data = abi.encode(uint256 start, uint256 limit); returns abi.encode(queueView).
    function getPendingImports(bytes calldata data) external view returns (bytes memory) {
        (uint256 start, uint256 limit) = abi.decode(data, (uint256, uint256));
        VerusObjects.pendingImportView[] memory queueView = _getPendingImportsByRange(start, limit);
        return abi.encode(queueView);
    }

    /// @dev Shared implementation for both getPendingImports overloads.
    ///      Reads queue positions [start, min(start+limit, length)) and returns view structs.
    function _getPendingImportsByRange(uint256 start, uint256 limit)
        private
        view
        returns (VerusObjects.pendingImportView[] memory queueView)
    {
        bytes32[] memory queue = _loadPendingQueue();
        uint256 queueLength = queue.length;
        if (start >= queueLength || limit == 0) {
            return new VerusObjects.pendingImportView[](0);
        }

        uint256 end = start + limit;
        if (end > queueLength) {
            end = queueLength;
        }

        queueView = new VerusObjects.pendingImportView[](end - start);
        for (uint256 i = start; i < end; i++) {
            VerusObjects.pendingImport memory pending = _loadPendingImport(_pendingImportKey(queue[i]));
            queueView[i - start] = _toPendingImportView(pending);
        }
    }

    /// @dev Derives the storageGlobal key for a pending import entry from its txid.
    function _pendingImportKey(bytes32 importTxid) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(PENDING_IMPORT_KEY_PREFIX, importTxid));
    }

    /// @dev Reads, increments, and stores the global nonce counter; returns the new value.
    ///      Nonces start at 1 and are used to make each import's digest unique even for identical data.
    function _nextPendingImportNonce() private returns (uint64) {
        bytes memory nonceData = storageGlobal[PENDING_IMPORT_NONCE_COUNTER_KEY];
        uint64 nextNonce = nonceData.length == 0 ? 1 : abi.decode(nonceData, (uint64)) + 1;
        storageGlobal[PENDING_IMPORT_NONCE_COUNTER_KEY] = abi.encode(nextNonce);
        return nextNonce;
    }

    /// @dev Loads and ABI-decodes a pendingImport from storageGlobal. Returns a zeroed struct if not found.
    function _loadPendingImport(bytes32 pendingKey) private view returns (VerusObjects.pendingImport memory pending) {
        bytes memory pendingData = storageGlobal[pendingKey];
        if (pendingData.length != 0) {
            pending = abi.decode(pendingData, (VerusObjects.pendingImport));
        }
    }

    /// @dev Converts the internal pendingImport storage struct into a read-friendly pendingImportView,
    ///      pairing each transfer with its optional launch data and annotating the output type (1=transfer, 2=launch).
    function _toPendingImportView(VerusObjects.pendingImport memory pending)
        private
        pure
        returns (VerusObjects.pendingImportView memory viewRow)
    {
        uint256 outputCount = pending.transfers.length;
        VerusObjects.pendingImportOutput[] memory outputs = new VerusObjects.pendingImportOutput[](outputCount);

        for (uint256 i = 0; i < outputCount; i++) {
            outputs[i].transfer = pending.transfers[i];

            uint32 launchIdx = pending.transfers[i].launchTxIndexPlusOne;
            if (launchIdx > 0 && launchIdx <= pending.launchTxs.length) {
                outputs[i].outputType = 2;
                outputs[i].launch = pending.launchTxs[launchIdx - 1];
            } else {
                outputs[i].outputType = 1;
            }
        }

        viewRow.txid = pending.importTxid;
        viewRow.nout = pending.nout;
        viewRow.outputs = outputs;
    }

    /// @dev Loads the ordered array of pending import txids from storageGlobal.
    ///      Returns an empty array if no imports are queued.
    function _loadPendingQueue() private view returns (bytes32[] memory queue) {
        bytes memory queueData = storageGlobal[PENDING_IMPORT_QUEUE_KEY];
        if (queueData.length != 0) {
            queue = abi.decode(queueData, (bytes32[]));
        } else {
            queue = new bytes32[](0);
        }
    }

    /// @dev Appends importTxid to the in-memory queue array by extending it in-place via assembly
    ///      (avoids a full copy loop), then persists the updated array and the index mapping.
    ///
    ///      Memory safety: `_loadPendingQueue` always returns a freshly allocated array whose last
    ///      element sits exactly at the free pointer on return (abi.decode advances the pointer to
    ///      `array + 0x20 + len*0x20`; `new bytes32[](0)` advances it to `array + 0x20`).
    ///      We read the free pointer directly with `mload(0x40)` instead of recomputing it from
    ///      `queue`, so the write is guaranteed to land at the actual free pointer regardless of
    ///      any future change to the load function, and the block is annotated `"memory-safe"`.
    function _enqueuePendingImport(bytes32 importTxid) private {
        bytes32[] memory queue = _loadPendingQueue();
        uint256 len = queue.length;
        assembly {
            // mload(0x40) is the free pointer, which equals queue + 0x20 + len*0x20
            // immediately after _loadPendingQueue (no allocation in between).
            // Writing here and then advancing the free pointer is the standard safe pattern.
            let slot := mload(0x40)
            mstore(slot, importTxid)
            mstore(queue, add(len, 1))
            mstore(0x40, add(slot, 0x20))
        }
        storageGlobal[PENDING_IMPORT_QUEUE_KEY] = abi.encode(queue);
        storageGlobal[keccak256(abi.encodePacked(PENDING_IMPORT_QUEUE_INDEX_PREFIX, importTxid))] = abi.encode(len);
    }

    /// @dev Removes importTxid from the queue using swap-and-pop: the last element fills the vacated
    ///      slot and the array length is shrunk in-place via assembly, avoiding a full shift loop.
    ///      The index mapping for any moved element is updated accordingly.
    function _dequeuePendingImport(bytes32 importTxid) private {
        bytes32 indexSlotKey = keccak256(abi.encodePacked(PENDING_IMPORT_QUEUE_INDEX_PREFIX, importTxid));
        bytes memory indexData = storageGlobal[indexSlotKey];
        if (indexData.length == 0) return;

        bytes32[] memory queue = _loadPendingQueue();
        
        uint256 qLen = queue.length;
        if (qLen == 0) {
            delete storageGlobal[indexSlotKey];
            return;
        }

        uint256 idx = abi.decode(indexData, (uint256));
        uint256 last = qLen - 1;
        require(queue[idx] == importTxid);

        if (idx <= last && idx != last) {
            bytes32 movedTxid = queue[last];
            queue[idx] = movedTxid;
            storageGlobal[keccak256(abi.encodePacked(PENDING_IMPORT_QUEUE_INDEX_PREFIX, movedTxid))] = abi.encode(idx);
        }

        assembly { mstore(queue, last) }
        storageGlobal[PENDING_IMPORT_QUEUE_KEY] = abi.encode(queue);
        delete storageGlobal[indexSlotKey];
    }

    // -------------------------------------------------------------------------
    // Notary identity/index resolution by msg.sender (main address).
    // -------------------------------------------------------------------------
    function _resolveNotaryIndexFromSender() internal view returns (uint256) {
        for (uint256 i = 0; i < notaries.length; i++) {
            if (notaryAddressMapping[notaries[i]].main == msg.sender) {
                require(notaryAddressMapping[notaries[i]].state == VerusConstants.NOTARY_VALID);
                return i;
            }
        }
        return type(uint256).max;
    }

    function _resolveNotaryIAddress() internal view returns (address) {
        uint256 idx = _resolveNotaryIndexFromSender();
        return idx == type(uint256).max ? address(0) : notaries[idx];
    }

    /// @notice Returns the notary i-address whose .main ETH address matches mainAddress.
    ///         Returns address(0) if mainAddress is not a registered notary main address.
    ///         The bridgekeeper calls this once at startup and caches the result for logging.
    function getNotaryIAddress() external view returns (address) {
        return _resolveNotaryIAddress();
    }

    function _loadHaltVoteBitmap() private view returns (uint32 bitmap) {
        if (storageGlobal[HALT_VOTE_BITMAP_KEY].length != 0) {
            bitmap = abi.decode(storageGlobal[HALT_VOTE_BITMAP_KEY], (uint32));
        }
    }

    function _submitHaltVote(bool voteToHalt) private {

        require(notaries.length > 0 && notaries.length <= 32);
        require(storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD].length == 0);
        storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD] = abi.encodePacked(uint8(1));

        uint256 notaryIndex = _resolveNotaryIndexFromSender();
        require(notaryIndex != type(uint256).max);
        address iAddr = notaries[notaryIndex];

        uint32 bitmap = _loadHaltVoteBitmap();
        uint32 mask = uint32(1) << uint32(notaryIndex);
        bool bridgePaused = storageGlobal[BRIDGE_PAUSED_KEY].length != 0;

        if (voteToHalt) {
            if ((bitmap & mask) == 0) {
                bitmap |= mask;
                storageGlobal[HALT_VOTE_BITMAP_KEY] = abi.encode(bitmap);
            }
        } else {
            // allow notary to rescind their halt vote if the bridge is not already paused and they have previously voted to halt
            uint256 voteCountBefore = _countSetBits32(bitmap);
            require(!bridgePaused);
            require(voteCountBefore < 3);

            if ((bitmap & mask) != 0) {
                bitmap &= ~mask;
                storageGlobal[HALT_VOTE_BITMAP_KEY] = abi.encode(bitmap);
            }
        }

        uint256 voteCount = _countSetBits32(bitmap);
        if (voteCount >= 3 && !bridgePaused) {
            storageGlobal[BRIDGE_PAUSED_KEY] = abi.encode(true);
            claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] =
                VerusConstants.HALT_SUBMIT_IMPORTS +
                VerusConstants.HALT_NOTARIZATIONS +
                VerusConstants.HALT_SEND_TRANSFERS;
            bridgePaused = true;
            emit BridgePaused();
        }

        emit HaltVoteSubmitted(iAddr, voteToHalt, voteCount, bridgePaused);
        delete storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD];
    }


    /// @notice Single notary entry point: records an approve or reject vote for a pending import and,
    ///         when that vote completes quorum, immediately executes (approve) or rejects and halts
    ///         the bridge (reject) in the same transaction — no follow-up call is required.
    /// @dev    Checks are ordered cheapest-first so that losing races (a notary voting on an import
    ///         that another notary just completed, or double voting) revert before any expensive
    ///         storage decode of the pending import record.
    function _approveOrRejectAcceptedImport(bytes32 importTxid, bool approve) private {

        require(storageGlobal[BRIDGE_PAUSED_KEY].length == 0);
        require(storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD].length == 0);

        // Single length-slot read: the import is gone as soon as it has been executed.
        bytes32 pendingKey = _pendingImportKey(importTxid);
        require(storageGlobal[pendingKey].length != 0);

        uint256 notaryCount = notaries.length;
        require(notaryCount > 0 && notaryCount <= 32);

        uint256 notaryIndex = _resolveNotaryIndexFromSender();
        require(notaryIndex != type(uint256).max);

        bytes32 voteKey = keccak256(abi.encodePacked(approve ? RELEASE_VOTE_BITMAP_PREFIX : REJECT_VOTE_BITMAP_PREFIX, importTxid));
        uint32 bitmap = storageGlobal[voteKey].length == 0
            ? uint32(0)
            : abi.decode(storageGlobal[voteKey], (uint32));

        uint32 mask = uint32(1) << uint32(notaryIndex);
        require((bitmap & mask) == 0);

        // Only decode the full record once the caller is known to be an eligible first-time voter.
        VerusObjects.pendingImport memory pending = _loadPendingImport(pendingKey);
        require(pending.state == IMPORT_STATE_PENDING);
        // Approvals wait out the cooldown; rejections may be cast immediately.
        require(!approve || block.timestamp >= uint256(pending.submittedAt) + IMPORT_RELEASE_COOLDOWN);

        storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD] = abi.encodePacked(uint8(1));

        bitmap |= mask;
        storageGlobal[voteKey] = abi.encode(bitmap);

        uint256 count = _countSetBits32(bitmap);
        uint256 quorum = (notaryCount >> 1) + 1;
        address iAddr = notaries[notaryIndex];

        if (approve) {
            emit PendingImportApproved(importTxid, iAddr, count);
            if (count >= quorum) {
                _executeImport(importTxid, pendingKey, pending);
            }
        } else {
            emit PendingImportRejectVote(importTxid, iAddr, count);
            if (count >= quorum) {
                _rejectImport(importTxid, pendingKey, pending);
            }
        }

        delete storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD];
    }

    /// @dev Marks the import permanently rejected (it stays queued so the daemon can observe the
    ///      final state) and halts the bridge.
    function _rejectImport(
        bytes32 importTxid,
        bytes32 pendingKey,
        VerusObjects.pendingImport memory pending
    ) private {

        pending.state = IMPORT_STATE_REJECTED;
        storageGlobal[pendingKey] = abi.encode(pending);

        if (storageGlobal[BRIDGE_PAUSED_KEY].length == 0) {
            storageGlobal[BRIDGE_PAUSED_KEY] = abi.encode(true);
            claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] =
                VerusConstants.HALT_SUBMIT_IMPORTS +
                VerusConstants.HALT_NOTARIZATIONS +
                VerusConstants.HALT_SEND_TRANSFERS;
            emit BridgePaused();
        }

        emit PendingImportRejected(importTxid);
    }

    function _executeTimedOutImport(bytes32 importTxid) private {

        require(storageGlobal[BRIDGE_PAUSED_KEY].length == 0);
        if (claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] != 0) revert();
        require(storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD].length == 0);
        storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD] = abi.encodePacked(uint8(1));

        bytes32 pendingKey = _pendingImportKey(importTxid);
        VerusObjects.pendingImport memory pending = _loadPendingImport(pendingKey);
        require(pending.state == IMPORT_STATE_PENDING);
        require(block.timestamp >= uint256(pending.submittedAt) + IMPORT_RELEASE_COOLDOWN + IMPORT_TIMEOUT);

        _executeImport(importTxid, pendingKey, pending);
        delete storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD];
    }

    // -------------------------------------------------------------------------
    // VDXF dispatch overloads — called via Delegator.setVerusData(data, name).
    // Each decodes the bytes payload and delegates to the typed function above.
    // msg.sender is preserved through delegatecall so identity checks still work.
    // -------------------------------------------------------------------------

    /// @notice VDXF path: data = abi.encode(bytes32 importTxid, bool approve)
    function approveOrRejectAcceptedImport(bytes calldata data) external {
        (bytes32 importTxid, bool approve) = abi.decode(data, (bytes32, bool));
        _approveOrRejectAcceptedImport(importTxid, approve);
    }

    /// @notice VDXF path: data = abi.encode(bool voteToHalt)
    function submitHaltVote(bytes calldata data) external {
        _submitHaltVote(abi.decode(data, (bool)));
    }
    /// @notice VDXF path: data = abi.encode(bytes32 importTxid)
    function executeTimedOutImport(bytes calldata data) external {
        _executeTimedOutImport(abi.decode(data, (bytes32)));
    }

    /// @notice VDXF path: returns abi.encode(bool) — bridge paused status.
    function isBridgePaused(bytes calldata) external view returns (bytes memory) {
        return abi.encode(storageGlobal[BRIDGE_PAUSED_KEY].length != 0);
    }

    /// @notice VDXF path: returns abi.encode(address) — notary i-address for msg.sender.
    function getNotaryIAddress(bytes calldata) external view returns (bytes memory) {
        return abi.encode(_resolveNotaryIAddress());
    }

    // -------------------------------------------------------------------------
    // Status helpers.
    // -------------------------------------------------------------------------

    /// @notice Returns true if the bridge has been paused by 3 notary halt votes.
    function isBridgePaused() external view returns (bool) {
        return storageGlobal[BRIDGE_PAUSED_KEY].length != 0;
    }

    // -------------------------------------------------------------------------
    // Private: execute an approved or timed-out import.
    // Sets state to RELEASED (prevents re-entry), then delegates to SubmitImports.
    // -------------------------------------------------------------------------
    /// @dev Marks the import as RELEASED (re-entrancy guard), delegatecalls SubmitImports to process
    ///      the transfers, then removes the import from queue and storage.
    function _executeImport(
        bytes32 importTxid,
        bytes32 pendingKey,
        VerusObjects.pendingImport memory pending
    ) private {
        // Safety latch: once paused by halt quorum, no further pending imports can execute.
        require(storageGlobal[BRIDGE_PAUSED_KEY].length == 0);
        if (claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] != 0) revert();

        pending.state = IMPORT_STATE_RELEASED;
        storageGlobal[pendingKey] = abi.encode(pending);

        address logic = contracts[uint(VerusConstants.ContractType.Imports)];
        (bool success,) = logic.delegatecall(
            abi.encodeWithSignature("executePendingImport(bytes32)", importTxid)
        );
        require(success);

        _dequeuePendingImport(importTxid);
        delete storageGlobal[pendingKey];
        delete storageGlobal[keccak256(abi.encodePacked(RELEASE_VOTE_BITMAP_PREFIX, importTxid))];
        delete storageGlobal[keccak256(abi.encodePacked(PENDING_EXEC_DATA_PREFIX, importTxid))];
        delete storageGlobal[keccak256(abi.encodePacked(PENDING_EXEC_PARAMS_PREFIX, importTxid))];

        emit PendingImportReleased(importTxid, msg.sender);
    }

}
