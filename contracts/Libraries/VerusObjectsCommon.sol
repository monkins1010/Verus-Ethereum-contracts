// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
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
