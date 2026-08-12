// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

import "./Token.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjects.sol";
import {VerusSerializer} from "../VerusBridge/VerusSerializer.sol";
import "../Storage/StorageMaster.sol";
import "./PendingImports.sol";


contract TokenManager is VerusStorage {

    // Immutables kept for deployment-script compatibility; execution logic moved to Imports.sol.
    address immutable VETH;
    address immutable VERUS;
    address immutable DAIERC20ADDRESS;

    bytes32 constant IMPORT_PENDING_CONTRACT_INDEX_KEY = keccak256("PendingImports.contract.index");
    // Must match the keys used in Imports.sol.processTransactionsDecoded / executePendingImport.
    bytes32 constant PENDING_EXEC_DATA_PREFIX   = keccak256("pending.exec.data");
    bytes32 constant PENDING_EXEC_PARAMS_PREFIX = keccak256("pending.exec.params");
    uint32 constant FORKS_TXID_POSITION = 0x40;
    uint32 constant FORKS_NOTARIZATION_N_POSITION = 0x44;

    constructor(address vETH, address, address Verus, address DaiERC20Address) {
        VETH            = vETH;
        VERUS           = Verus;
        DAIERC20ADDRESS = DaiERC20Address;
    }

    //reset to empty 9-July-26
    function initialize() external {}

    // ── Token registry ────────────────────────────────────────────────────
    // Also callable from Imports.launchToken via the shared delegatecall context.

    function recordToken(
        address _iaddress,
        address ethContractAddress,
        string memory name,
        string memory ticker,
        uint8 flags,
        uint256 tokenID
    ) public {

        address ERCContract;

        if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) {
            if (flags & VerusConstants.MAPPING_ERC20_DEFINITION == VerusConstants.MAPPING_ERC20_DEFINITION) {
                Token t = new Token(name, ticker);
                ERCContract = address(t);
            } else if (flags & VerusConstants.MAPPING_ERC721_NFT_DEFINITION == VerusConstants.MAPPING_ERC721_NFT_DEFINITION) {
                ERCContract = verusToERC20mapping[tokenList[VerusConstants.NFT_POSITION]].erc20ContractAddress;
                tokenID = uint256(uint160(_iaddress));
            }
        } else {
            ERCContract = ethContractAddress;
        }

        tokenList.push(_iaddress);
        verusToERC20mapping[_iaddress] = VerusObjects.mappedToken(ERCContract, flags, 0, name, tokenID);
    }

    // ── Import queuing ────────────────────────────────────────────────────
    // Deserialises transfers, queues the import in PendingImports, and stores
    // two compact execution records consumed later by Imports.executePendingImport.

    function processTransactions(
        bytes calldata serializedTransfers,
        uint128 cceHeightsAndIndex,
        bytes32 importTxid,
        uint176[3] calldata exporters
    ) external {

        VerusObjects.PackedSend[] memory transfers;
        VerusObjects.PackedCurrencyLaunch[] memory launchTxs;
        uint64 fees;
        uint8 numberOfTransfers = uint8(uint32(cceHeightsAndIndex >> 96));

        (transfers, launchTxs, fees) = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)])
            .deserializeTransfers(serializedTransfers, numberOfTransfers);

        _queuePendingImport(importTxid, cceHeightsAndIndex, transfers, launchTxs, fees, exporters);

        // exec data  → consumed by Imports.processTransactionsDecoded (token payouts)
        storageGlobal[keccak256(abi.encodePacked(PENDING_EXEC_DATA_PREFIX, importTxid))] =
            abi.encode(transfers, launchTxs, fees);

        // exec params → consumed by Imports.executePendingImport (fee accounting)
        storageGlobal[keccak256(abi.encodePacked(PENDING_EXEC_PARAMS_PREFIX, importTxid))] =
            abi.encode(cceHeightsAndIndex, exporters);
    }

    function _queuePendingImport(
        bytes32 importTxid,
        uint128 cceHeightsAndIndex,
        VerusObjects.PackedSend[] memory transfers,
        VerusObjects.PackedCurrencyLaunch[] memory launchTxs,
        uint64 fees,
        uint176[3] calldata exporters
    ) private {
        bytes32 txid;
        uint32 vout;
        bytes memory proposerBytes = bestForks[0];
        bytes32 proposerPacked;
        assembly {
            txid := mload(add(proposerBytes, 0x40))
            proposerPacked := mload(add(proposerBytes, 0x60))
        }
        vout = uint32(uint256(proposerPacked >> VerusConstants.NOTARIZATION_VOUT_NUM_INDEX));

        (bool success,) = contracts[getPendingIndexData()].delegatecall(
            abi.encodeWithSelector(
                PendingImports.queuePendingImport.selector,
                importTxid,
                uint32(cceHeightsAndIndex >> 64),
                txid,
                vout,
                cceHeightsAndIndex,
                transfers,
                launchTxs,
                fees,
                exporters
            )
        );
        require(success, "Queue failed");
    }

    function getPendingIndexData() public view returns (uint256) {
        bytes memory pendingIndexData = storageGlobal[IMPORT_PENDING_CONTRACT_INDEX_KEY];
        require(pendingIndexData.length != 0);
        return abi.decode(pendingIndexData, (uint256));
    }
}
