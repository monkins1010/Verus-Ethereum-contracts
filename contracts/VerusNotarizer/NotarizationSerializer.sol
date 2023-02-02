// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0;
pragma abicoder v2;
import "../Libraries/VerusObjects.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../VerusNotarizer/VerusNotarizer.sol";

contract NotarizationSerializer {

    VerusSerializer verusSerializer;

    uint8 constant CURRENCY_LENGTH = 20;
    uint8 constant BYTES32_LENGTH = 32;
    uint8 constant TWO2BYTES32_LENGTH = 64;
    uint8 constant FLAG_FRACTIONAL = 1;
    uint8 constant FLAG_REFUNDING = 4;
    uint8 constant FLAG_LAUNCHCONFIRMED = 0x10;
    uint8 constant FLAG_LAUNCHCOMPLETEMARKER = 0x20;

    address verusUpgradeContract;

    constructor(address verusUpgradeAddress, address verusSerializerAddress) 
    {
        verusUpgradeContract = verusUpgradeAddress;
        verusSerializer = VerusSerializer(verusSerializerAddress);
    }

    function setContract(address serializerContract) public {

        require(msg.sender == verusUpgradeContract);

        verusSerializer = VerusSerializer(serializerContract);
        
    }

    function readVarint(bytes memory buf, uint32 idx) public pure returns (uint32 v, uint32 retidx) {

        uint8 b; // store current byte content

        for (uint32 i=0; i<10; i++) {
            b = uint8(buf[i+idx]);
            v = (v << 7) | b & 0x7F;
            if (b & 0x80 == 0x80)
                v++;
            else
            return (v, idx + i + 1);
        }
        revert(); // i=10, invalid varint stream
    }

    function deserilizeNotarization(bytes memory notarization) public view returns (bytes32 proposerAndLaunched, bytes32 prevnotarizationtxid, bytes32 hashprevcrossnotarization, bytes32 stateRoot
                                                                                        , bytes32 blockHash , uint32 height  ) {
        
        uint32 nextOffset;
        uint16 bridgeLaunched;

        VerusObjectsCommon.UintReader memory readerLen;

        readerLen = readVarintStruct(notarization, 0);    // get the length of the varint version
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the flags

        nextOffset = readerLen.offset;

        assembly {
                    nextOffset := add(nextOffset, 22) // CHECK: skip proposer type and vector length
                    proposerAndLaunched := and(mload(add(nextOffset, notarization)), 0x00000000000000000000ffffffffffffffffffffffffffffffffffffffffffff)   // type+len+proposer 22bytes
                    nextOffset := add(nextOffset, CURRENCY_LENGTH) //skip currencyid
                 }

        (, nextOffset) = deserializeCoinbaseCurrencyState(notarization, nextOffset);

        assembly {
                    nextOffset := add(nextOffset, 4) // skip notarizationheight
                    nextOffset := add(nextOffset, BYTES32_LENGTH) // move to read prevnotarizationtxid
                    prevnotarizationtxid := mload(add(notarization, nextOffset))      // prevnotarizationtxid 
                    nextOffset := add(nextOffset, 4) //skip prevnotarizationout
                    nextOffset := add(nextOffset, BYTES32_LENGTH) // move to read hashprevcrossnotarization
                    hashprevcrossnotarization := mload(add(notarization, nextOffset))      // hashprevcrossnotarization 
                    nextOffset := add(nextOffset, 4) //skip prevheight
                    nextOffset := add(nextOffset, 1) //skip prevheight
                }

        readerLen = verusSerializer.readCompactSizeLE(notarization, nextOffset);    // get the length of the currencyState

        nextOffset = readerLen.offset - 1;   //readCompactSizeLE returns 1 byte after and wants one byte after 

        for (uint i = 0; i < readerLen.value; i++)
        {
            uint16 temp;
            (temp, nextOffset) = deserializeCoinbaseCurrencyState(notarization, nextOffset);
            bridgeLaunched = temp | bridgeLaunched;
        }

        proposerAndLaunched |= bytes32(uint256(bridgeLaunched) << 176);  // Shift 16bit value 22 bytes to pack in bytes32

        nextOffset++; //move forwards to read le
        readerLen = verusSerializer.readCompactSizeLE(notarization, nextOffset);    // get the length of proofroot array

        (stateRoot, blockHash, height) = deserializeProofRoots(notarization, uint32(readerLen.value), nextOffset);

    }

    function deserializeCoinbaseCurrencyState(bytes memory notarization, uint32 nextOffset) private view returns (uint16, uint32)
    {
        
        address currencyid;
        uint16 bridgeLaunched;
        uint16 flags;
        
        assembly {
            nextOffset := add(nextOffset, 2) // skip version
            nextOffset := add(nextOffset, 2) // move to flags
            flags := mload(add(notarization, nextOffset))      // flags 
            nextOffset := add(nextOffset, CURRENCY_LENGTH) //skip notarization currencystatecurrencyid
            currencyid := mload(add(notarization, nextOffset))      // currencyid 
        }
        flags = (flags >> 8) | (flags << 8);
        if ((currencyid == VerusConstants.VerusBridgeAddress) && flags & (FLAG_FRACTIONAL + FLAG_REFUNDING + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER) == 
            (FLAG_FRACTIONAL + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER)) 
        {
            bridgeLaunched = 1;
        }
        assembly {                    
                    
                    nextOffset := add(nextOffset, 1) // move to  read currency state length
        }
        VerusObjectsCommon.UintReader memory readerLen;

        readerLen = verusSerializer.readCompactSizeLE(notarization, nextOffset);        // get the length currencies

        nextOffset = nextOffset + (uint32(readerLen.value) * BYTES32_LENGTH) + 2;       // currencys, wights, reserves arrarys

        readerLen = readVarintStruct(notarization, nextOffset);        // get the length of the initialsupply
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the emitted
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the supply
        nextOffset = readerLen.offset;
        assembly {
                    nextOffset := add(nextOffset, 33) //skip coinbasecurrencystate first 4 items fixed at 4 x 8
                }

        readerLen = verusSerializer.readCompactSizeLE(notarization, nextOffset);    // get the length of the reservein array of uint64
        nextOffset = readerLen.offset + (uint32(readerLen.value) * 60) + 6;                 //skip 60 bytes of rest of state knowing array size always same as first

        return (bridgeLaunched, nextOffset);
    }

    function deserializeProofRoots (bytes memory notarization, uint32 size, uint32 nextOffset) private view returns (bytes32 stateRoot, bytes32 blockHash, uint32 height)
    {
        for (uint i = 0; i < size; i++)
        {
            uint16 proofType;
            address systemID;
            bytes32 tempStateRoot;
            bytes32 tempBlockHash;
            uint32 tempHeight;

            assembly {
                nextOffset := add(nextOffset, 2) // move to version
                nextOffset := add(nextOffset, 2) // move to read type
                proofType := mload(add(notarization, nextOffset))      // read proofType 
                nextOffset := add(nextOffset, CURRENCY_LENGTH) // move to read systemID
                systemID := mload(add(notarization, nextOffset))  
                nextOffset := add(nextOffset, 4) // move to height
                tempHeight := mload(add(notarization, nextOffset))  
                nextOffset := add(nextOffset, BYTES32_LENGTH) // move to read stateroot
                tempStateRoot := mload(add(notarization, nextOffset))  
                nextOffset := add(nextOffset, BYTES32_LENGTH) // move to read blockhash
                tempBlockHash := mload(add(notarization, nextOffset))  
                nextOffset := add(nextOffset, TWO2BYTES32_LENGTH) // move to power
            }
            
            if(systemID == VerusConstants.VerusCurrencyId)
            {
                stateRoot = tempStateRoot;
                blockHash = tempBlockHash;
                height = verusSerializer.serializeUint32(tempHeight); //swapendian
            }

            //swap 16bit endian
            if((proofType >> 8) == 2){ //IF TYPE ETHEREUM 
                assembly {
                nextOffset := add(nextOffset, 8) // skip gasprice
                }

            }

        }
 
    }

    function readVarintStruct(bytes memory buf, uint idx) public pure returns (VerusObjectsCommon.UintReader memory) {

        uint8 b; // store current byte content
        uint64 v; 

        for (uint i = 0; i < 10; i++) {
            b = uint8(buf[i+idx]);
            v = (v << 7) | b & 0x7F;
            if (b & 0x80 == 0x80)
                v++;
            else
            return VerusObjectsCommon.UintReader(uint32(idx + i + 1), v);
        }
        revert(); // i=9, invalid varint stream
    }
    
}


