// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./VerusObjectsCommon.sol";

library VerusObjects {

    struct blockCreated {
        uint index;
        bool created;
    }

    struct infoDetails {
        uint version;
        string VRSCversion;
        uint blocks;
        uint tiptime;
        string name;
        bool testnet;
    }
    
    struct currencyDetail {
        uint version;
        string name;
        address currencyid;
        address parent;
        address systemid;
        uint8 notarizationprotocol;
        uint8 proofprotocol;
        VerusObjectsCommon.CTransferDestination nativecurrencyid;
        address launchsystemid;
        uint startblock;
        uint endblock;
        uint256 initialsupply;
        uint256 prelaunchcarveout;
        address gatewayid;
        address[] notaries;
        uint minnotariesconfirm;
    }
    
    struct CCurrencyValueMap {
        address currency;
        uint64 amount;
    }

    struct CReserveTransfer {
        uint32 version;
        CCurrencyValueMap currencyvalue;
        uint32 flags;
        address feecurrencyid;
        uint256 fees;
        VerusObjectsCommon.CTransferDestination destination;
        address destcurrencyid;
        address destsystemid;
        address secondreserveid;
    }

    // CReserve Transfer Set is a simplified version of a crosschain export returning only the required info
    
    struct CReserveTransferSet {
        bytes32 exportHash;
        bytes32 prevExportHash;
        uint32 blockHeight;
        CReserveTransfer[] transfers;
    }

    struct LastImport {
        uint height;
        bytes32 txid;                                   // this is actually the hash of the transfers that can be used for proof
    }

    struct SimpleTransfer {
        address currency;
        uint64 currencyvalue;
        uint32 flags;
        uint256 fees;
        bytes destination;
        uint8 destinationType;

    }

    struct PackedSend {
        uint256 currencyAndAmount;
        uint256 destinationAndFlags;
        address nativeCurrency;
    }

    struct DeserializedObject {
        PackedSend[] transfers;
        uint32 counter;
    }

    struct Buffer {
        uint256 idx;  // the start index of next read. when idx=b.length, we're done
        bytes b;   // hold serialized data readonly
    }

    struct ETHPayments {
        address destination;  // the start index of next read. when idx=b.length, we're done
        uint256 amount;   // hold serialized data readonly
    }

    struct CReserveTransferImport {
        uint height;
        bytes32 txid;                                   // when from ETH, this is hash of the serialized CCrossChainExport that can be used for proof
        uint txoutnum;                                  // index of the transfers in the exports array
        CCrossChainExport exportinfo;
        CPtransactionproof partialtransactionproof;     // partial transaction proof is for the 
        bytes serializedTransfers;
    }

    struct CCrossChainExport {
        uint16 version;
        uint16 flags;
        address sourcesystemid;
        bytes32 hashtransfers;                          // hashtransfers
        uint32 sourceheightstart;
        uint32 sourceheightend;
        address destinationsystemid;
        address destinationcurrencyid;
        uint32 numinputs;
        CCurrencyValueMap[] totalamounts;
        CCurrencyValueMap[] totalfees;
        CCurrencyValueMap[] totalburned;
        VerusObjectsCommon.CTransferDestination rewardaddress; //reward address
        int32 firstinput;
    }

    struct CcurrencyDefinition {
         address parent;
         string name;
         address launchSystemID;
         address systemID;
         address nativeCurrencyID;
     }

    struct CMerkleBranch {
        uint8  CMerkleBranchBase;
        uint32 nIndex;
        uint32 nSize;
        bytes32[] branch;
    }

    struct CTXProof {
        uint8 branchType;
        CMerkleBranch proofSequence;
    }

    struct CComponents {
        uint8 elType;
        uint8 elIdx;
        bytes elVchObj;
        CTXProof[] elProof;
    }
    
    struct CPtransactionproof {
        uint8 version;
        uint8 typeC;
        CTXProof[] txproof;
        CComponents[] components;
    }

    struct mappedToken {
        address erc20ContractAddress;
        uint8 flags;
        uint tokenIndex;
    }

    struct setupToken {
        address iaddress;
        address erc20ContractAddress;
        address launchSystemID;
        uint8 flags;
        string name;
        string ticker;
    }

    struct upgradeContracts {

        uint8 _vs;
        bytes32 _rs;
        bytes32  _ss;
        address[] contracts;
        address notaryAddress;

    }

 }