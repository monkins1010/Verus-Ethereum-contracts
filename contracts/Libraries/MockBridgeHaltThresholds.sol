// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./BridgeHalt.sol";

/// @dev TEST ONLY. Exposes the BridgeHalt vote thresholds so tests can check notary set sizes
///      the 3-notary dev network cannot reach.
contract MockBridgeHaltThresholds {
    function rejectHaltThreshold(uint256 notaryCount) external pure returns (uint256) {
        return BridgeHalt.rejectHaltThreshold(notaryCount);
    }

    function quorum(uint256 notaryCount) external pure returns (uint256) {
        return BridgeHalt.quorum(notaryCount);
    }
}
