// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.1;
pragma abicoder v2;

import "./VerusObjectsCommon.sol";

library VerusObjectsProof {
    
    struct CMerkleBranch {

        uint8  CMerkleBranchBase;
        uint32 nIndex;
        uint32 nSize;
        uint8 extraHashes;
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
}