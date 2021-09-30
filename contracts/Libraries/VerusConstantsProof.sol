// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 < 0.9.0;
pragma experimental ABIEncoderV2;

import "./VerusObjectsCommon.sol";

library VerusObjectsProof {
    
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