// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
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
    bytes32 public lastTxIdImport;  //NOTE: not used and changed to a VDXFID

    uint64 public cceLastStartHeight;
    uint64 public cceLastEndHeight;

    //verusnotarizer storage

    bool public bridgeConverterActive;
    mapping (bytes32 => bytes) public storageGlobal;    // Generic storage location NOTE: After security verified, add Oracle proofs.
    mapping (bytes32 => bytes) internal proofs;         // Stored Verus stateroot/blockhash proofs indexed by height.
    mapping (bytes32 => uint256) public claimableFees;  // CreserveTransfer destinations mapped to Fees they have accrued.
    mapping (bytes32 => uint256) public refunds;        // Failed transaction refunds NOTE: Not used, see global storageGlobal, type 0x01

    uint64 remainingLaunchFeeReserves;   // Starts at 5000 VRSC

    //upgrademanager
    address[] public contracts;  // List of all known contracts Delegator trusts to use (contracts replacable on upgrade)

    VerusObjects.voteState[] public pendingVoteState; // Potential contract upgrades
    address[100] public rollingUpgradeVotes; 
    uint8 public rollingVoteIndex;
    mapping (bytes32 => bool) public saltsUsed;   //salts used for upgrades and revoking.

    // verusnotarizer
    
    mapping (address => VerusObjects.notarizer ) public notaryAddressMapping; // Mapping iaddress of notaries to their spend/recover ETH addresses
    mapping (bytes32 => bool) knownNotarizationTxids;

    address[] public notaries; // Notaries for enumeration

    bytes[] public bestForks; // Forks array

    address public owner;    // Testnet only owner to allow quick upgrades, TODO: Remove once Voting established.

}