// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 < 0.9.0;
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


    //CReserve Transfer Set is a simplified version of a crosschain export returning only the required info
    
    struct CReserveTransferSet {
        uint position;
        uint blockHeight;
        bytes32 exportHash;
        CReserveTransfer[] transfers;
    }

    struct LastImport {
        uint height;
        bytes32 txid; //this is actually the hash of the transfers that can be used for proof
    }

    struct CReserveTransferImport {
        uint height;
        bytes32 txid; //this is actually the hash of the transfers that can be used for proof
        uint txoutnum; //index of the transfers in the exports array
        CCrossChainExport exportinfo;
        CPtransactionproof partialtransactionproof;  //partial transaction proof is for the 
        CReserveTransfer[] transfers ;
    }

    struct CCrossChainExport {
        uint16 version;
        uint16 flags;
        address sourcesystemid;
        uint32 sourceheightstart;
        uint32 sourceheightend;
        address destinationsystemid;
        address destinationcurrencyid;
        uint32 numinputs;
        CCurrencyValueMap[] totalamounts;
        CCurrencyValueMap[] totalfees;
        bytes32 hashtransfers; // hashtransfers
        CCurrencyValueMap[] totalburned;
        VerusObjectsCommon.CTransferDestination rewardaddress; //reward address
        int32 firstinput;
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
        uint32 VchObjIndex;

    }
    
    struct CPtransactionproof {
        uint8 version;
        uint8 typeC;
        CTXProof[] txproof;
        CComponents[] components;
    }
}