// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../VerusBridge/Token.sol";
import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";


contract VerusStorage {

    //verusbridgestorage
    mapping (uint => VerusObjects.CReserveTransferSet) public _readyExports;
    mapping (uint => uint) public exportHeights;

    mapping (bytes32 => bool) public processedTxids;
    mapping (address => VerusObjects.mappedToken) public verusToERC20mapping;
    mapping (bytes32 => VerusObjects.lastImportInfo) public lastImportInfo;

    address[] public tokenList;
    bytes32 public lastTxIdImport;

    uint64 public cceLastStartHeight;
    uint64 public cceLastEndHeight;

    //verusnotarizaerstorage

    bool public poolAvailable;
    mapping (bytes32 => bytes32[]) public storageGlobal;
    mapping (bytes32 => bytes) internal proofs;
    mapping (bytes32 => uint256) public claimableFees;
    mapping (bytes32 => uint256) public refunds;

    //verusbridge

    uint64 poolSize;

    //upgrademanager
    address[] public contracts;

    mapping (address => VerusObjects.voteState) public pendingVoteState;

    mapping (bytes32 => bool) public saltsUsed;

    // verusnotarizer
    
    mapping (address => VerusObjects.notarizer ) public notaryAddressMapping;
    mapping (bytes32 => bool) knownNotarizationTxids;

    address[] public notaries;

    bytes[] public bestForks;

    address public owner;

    uint64 public lastRecievedGasPrice;
}