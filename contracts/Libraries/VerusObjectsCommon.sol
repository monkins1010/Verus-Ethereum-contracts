// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.1;
pragma abicoder v2;

library VerusObjectsCommon {
    struct CTransferDestination {
        uint8 destinationtype;
        bytes destinationaddress;
    }
    
    struct UintReader {
        uint32 offset;
        uint64 value;
    }
}
