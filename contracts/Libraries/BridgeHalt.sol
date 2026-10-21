// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
pragma abicoder v2;

import "./VerusConstants.sol";

/// @notice Single source of truth for the bridge halt states. See docs/BRIDGE-HALT-VOTING.md.
///
///  State                          Set by                                          Cleared by
///  ------------------------------ ----------------------------------------------- ---------------------------------
///  CONTRACTS_TEMPORARY_HALTED     4 or more notaries revoked (NotaryTools)        quorum of submitUnhaltVote votes
///  CONTRACTS_PERMANENTLY_HALTED   quorum of reject votes on one import txid       contract upgrade -> initialize()
///                                 (also clears any temporary halt and its votes)
///
/// Each state has its own storageGlobal key. The gates in the other contracts only read the
/// derived bit flags in claimableFees[VDXF_DISABLE_CONTRACT_KEY], which refreshFlags() rebuilds.
library BridgeHalt {

    uint8 constant CONTRACTS_NORMAL             = 0;
    uint8 constant CONTRACTS_TEMPORARY_HALTED   = 1;
    uint8 constant CONTRACTS_PERMANENTLY_HALTED = 2;

    // Both halts stop all value movement but leave notarizations (setLatestData) running: upgrade votes ride
    // in notarizations, so stopping them could leave a bridge with unrecoverable notaries with no way out.
    // A notarization still needs a notary quorum, so a revoked minority cannot forge one.
    // = HALT_SUBMIT_IMPORTS (2) + HALT_SEND_TRANSFERS (4)
    uint8 constant TEMPORARY_HALT_FLAGS = 6;
    uint8 constant PERMANENT_HALT_FLAGS = 6;

    // The temporary halt triggers when this many notaries are revoked ("more than 3").
    uint8 constant REVOKED_HALT_THRESHOLD = 4;

    bytes32 constant TEMPORARY_HALTED_KEY      = keccak256("bridge.temporary.halted");
    // Holds abi.encode(bytes32 blockedTxid) while permanently halted.
    bytes32 constant PERMANENTLY_HALTED_KEY    = keccak256("bridge.permanently.halted");
    bytes32 constant UNHALT_VOTE_BITMAP_KEY    = keccak256("bridge.unhalt.vote.bitmap");
    // Holds abi.encode(uint256 timestamp) of the last time any halt was lifted.
    bytes32 constant HALT_LIFTED_AT_KEY        = keccak256("bridge.halt.lifted.at");

    function isTemporarilyHalted(mapping(bytes32 => bytes) storage g) internal view returns (bool) {
        return g[TEMPORARY_HALTED_KEY].length != 0;
    }

    function isPermanentlyHalted(mapping(bytes32 => bytes) storage g) internal view returns (bool) {
        return g[PERMANENTLY_HALTED_KEY].length != 0;
    }

    /// @dev Records that a halt was just lifted. Pending imports must get their full review window again from here.
    function markHaltLifted(mapping(bytes32 => bytes) storage g) internal {
        g[HALT_LIFTED_AT_KEY] = abi.encode(block.timestamp);
    }

    /// @return Timestamp of the last halt lift, 0 if no halt was ever lifted.
    function haltLiftedAt(mapping(bytes32 => bytes) storage g) internal view returns (uint256) {
        bytes memory data = g[HALT_LIFTED_AT_KEY];
        return data.length == 0 ? 0 : abi.decode(data, (uint256));
    }

    /// @return NORMAL, TEMPORARY_HALTED or PERMANENTLY_HALTED (the two are mutually exclusive).
    function currentState(mapping(bytes32 => bytes) storage g) internal view returns (uint8) {
        if (isPermanentlyHalted(g)) return CONTRACTS_PERMANENTLY_HALTED;
        if (isTemporarilyHalted(g)) return CONTRACTS_TEMPORARY_HALTED;
        return CONTRACTS_NORMAL;
    }

    /// @dev Rebuilds the gate flags from the state keys. Call after any state key changes.
    function refreshFlags(
        mapping(bytes32 => bytes) storage g,
        mapping(bytes32 => uint256) storage flagStore
    ) internal {
        uint8 flags;
        if (isTemporarilyHalted(g)) flags |= TEMPORARY_HALT_FLAGS;
        if (isPermanentlyHalted(g)) flags |= PERMANENT_HALT_FLAGS;

        if (flags == 0) {
            delete flagStore[VerusConstants.VDXF_DISABLE_CONTRACT_KEY];
        } else {
            flagStore[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] = flags;
        }
    }

    /// @dev Enters CONTRACTS_TEMPORARY_HALTED with a fresh set of unhalt votes.
    function enterTemporaryHalt(
        mapping(bytes32 => bytes) storage g,
        mapping(bytes32 => uint256) storage flagStore
    ) internal {
        g[TEMPORARY_HALTED_KEY] = abi.encode(true);
        delete g[UNHALT_VOTE_BITMAP_KEY];
        refreshFlags(g, flagStore);
    }

    /// @dev Enters CONTRACTS_PERMANENTLY_HALTED recording the bad txid. Any temporary halt and its
    ///      unhalt votes are cleared: the unhalt endpoint is closed from here on and notarizations
    ///      resume so an upgrade can be voted in.
    function enterPermanentHalt(
        mapping(bytes32 => bytes) storage g,
        mapping(bytes32 => uint256) storage flagStore,
        bytes32 blockedTxid
    ) internal {
        g[PERMANENTLY_HALTED_KEY] = abi.encode(blockedTxid);
        delete g[TEMPORARY_HALTED_KEY];
        delete g[UNHALT_VOTE_BITMAP_KEY];
        refreshFlags(g, flagStore);
    }

    /// @dev Number of notaries needed for a quorum majority.
    function quorum(uint256 notaryCount) internal pure returns (uint256) {
        return (notaryCount >> 1) + 1;
    }

    /// @dev Revoked notaries needed to halt; capped at the notary count so small (test) notary sets can still halt.
    function revokedHaltThreshold(uint256 notaryCount) internal pure returns (uint256) {
        return notaryCount < REVOKED_HALT_THRESHOLD ? notaryCount : REVOKED_HALT_THRESHOLD;
    }
}
