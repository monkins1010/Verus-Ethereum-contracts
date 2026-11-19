// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

/// @notice Flow marker for logic functions that must only run as a step of a Delegator entry point.
///         All logic contracts run in the Delegator's storage by delegatecall, so they cannot tell an internal
///         call from an external one by msg.sender. The entry point that starts a flow records it here, and
///         every internal-only function requires one of the flows it belongs to. A function reached any
///         other way (for example through a setVerusData route) finds no flow and reverts.
///         Entry points save the previous value and restore it, so flows nest and the slot is zero between
///         transactions. A reverted call restores the slot with the rest of its state.
library InternalCall {

    // claimableFees key holding the active flow. Not a 22-byte destination, so no fee or system key can alias it.
    bytes32 constant FLOW_KEY = keccak256("veth.internal.call.flow");

    uint256 constant SUBMIT_IMPORT  = 1;    // SubmitImports._createImports
    uint256 constant EXECUTE_IMPORT = 2;    // PendingImports._executeImport
    uint256 constant CLAIM_REFUND   = 4;    // SubmitImports.claimRefund
    uint256 constant SEND_FEES      = 8;    // SubmitImports.sendfees
    uint256 constant SEND_TRANSFER  = 16;   // CreateExports.sendTransferMain
    uint256 constant BURN_FEES      = 32;   // CreateExports.burnFees
    uint256 constant NOTARIZE       = 64;   // VerusNotarizer.checkNotarization
    uint256 constant LAUNCH_TOKENS  = 128;  // NotaryTools.launchContractTokens (owner setup)

    function enter(mapping(bytes32 => uint256) storage flags, uint256 flow) internal returns (uint256 previous) {
        previous = flags[FLOW_KEY];
        flags[FLOW_KEY] = flow;
    }

    function exit(mapping(bytes32 => uint256) storage flags, uint256 previous) internal {
        flags[FLOW_KEY] = previous;
    }

    function only(mapping(bytes32 => uint256) storage flags, uint256 allowedFlows) internal view {
        require(flags[FLOW_KEY] & allowedFlows != 0);
    }
}
