// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Storage/StorageMaster.sol";

/// @dev TEST ONLY. Stands in for the VerusProof slot so an import with chosen transfers can go through the real
///      submitImports, queue and release path without a Verus proof. proveImports() accepts any import and returns
///      the export heights / index / transfer count and exporters given to the constructor. initialize() (run when
///      it is installed) seeds the confirmed-notarization record bestForks[0] with the given proposer, record length
///      and proof-root height 0, and can switch the bridge to its launched state. Never deploy to production.
contract MockImportProof is VerusStorage {

    uint128 immutable CCE_HEIGHTS_AND_INDEX;
    uint176 immutable EXPORTER_MAIN;
    uint176 immutable EXPORTER_AUX;
    uint176 immutable PROPOSER;
    uint256 immutable FORKS_LENGTH;
    bool immutable LAUNCHED;

    constructor(uint128 cceHeightsAndIndex, uint176 exporterMain, uint176 exporterAux, uint176 proposer,
                uint256 forksLength, bool launched) {
        CCE_HEIGHTS_AND_INDEX = cceHeightsAndIndex;
        EXPORTER_MAIN = exporterMain;
        EXPORTER_AUX = exporterAux;
        PROPOSER = proposer;
        FORKS_LENGTH = forksLength;
        LAUNCHED = launched;
    }

    function initialize() external {
        // word 1: confirmed notarization txid; word 2: height (0) | vout (0) | proposer, as VerusNotarizer packs it
        bytes memory forks = new bytes(FORKS_LENGTH);
        bytes32 txid = keccak256("mock.notarization.txid");
        uint256 proposerWord = uint256(PROPOSER);
        assembly {
            mstore(add(forks, 0x40), txid)
            mstore(add(forks, 0x60), proposerWord)
        }
        if (bestForks.length == 0) {
            bestForks.push(forks);
        } else {
            bestForks[0] = forks;
        }
        if (LAUNCHED) {
            bridgeConverterActive = true;
        }
    }

    function proveImports(bytes calldata) external view returns (uint128, uint176, uint176, uint176) {
        return (CCE_HEIGHTS_AND_INDEX, EXPORTER_MAIN, EXPORTER_AUX, 0);
    }
}
