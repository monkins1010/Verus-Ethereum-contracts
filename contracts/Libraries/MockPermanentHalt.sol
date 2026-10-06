// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./BridgeHalt.sol";
import "../Storage/StorageMaster.sol";

/// @dev TEST ONLY. Stands in for a contract slot whose initialize() drops the bridge into
///      CONTRACTS_PERMANENTLY_HALTED, so tests can reach that state without a real rejected import.
contract MockPermanentHalt is VerusStorage {
    function initialize() external {
        BridgeHalt.enterPermanentHalt(storageGlobal, claimableFees, bytes32(uint256(0xbad)));
    }
}
