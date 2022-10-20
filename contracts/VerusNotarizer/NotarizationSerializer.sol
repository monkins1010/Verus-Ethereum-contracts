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

    function deserilizeNotarization(bytes memory notarization) public view returns (uint64, bytes32, bytes32) {
        uint32 nextOffset;
        uint64 packedPositions; // first 16bits proposer position, 2nd 16bits bridgelaunched 1 bit in 16bit uint, 3rd 16bits stateroot position
        bytes32 prevnotarizationtxid;
        bytes32 hashprevcrossnotarization; 
        uint32 staterootposition;
        uint16 bridgeLaunched;

        VerusObjectsCommon.UintReader memory readerLen;

        readerLen = readVarintStruct(notarization, 0);    // get the length of the varint version
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the flags

        nextOffset = readerLen.offset;
        packedPositions = nextOffset + CURRENCY_LENGTH;
        assembly {
                    nextOffset := add(nextOffset, CURRENCY_LENGTH) // CHECK: skip proposer type??
                  //  proposer := mload(add(notarization, nextOffset))      // proposer 
                 }

        deserializeCoinbaseCurrencyState(notarization, nextOffset);

        assembly {
                    nextOffset := add(nextOffset, 4) // skip notarizationheight
                    nextOffset := add(nextOffset, BYTES32_LENGTH) // move to read prevnotarizationtxid
                    prevnotarizationtxid := mload(add(notarization, nextOffset))      // prevnotarizationtxid 
                    nextOffset := add(nextOffset, 4) //skip prevnotarizationout
                    nextOffset := add(nextOffset, BYTES32_LENGTH) // move to read hashprevcrossnotarization
                    hashprevcrossnotarization := mload(add(notarization, nextOffset))      // hashprevcrossnotarization 
                    nextOffset := add(nextOffset, 4) //skip prevheight
                }

        readerLen = verusSerializer.readCompactSizeLE(notarization, nextOffset);    // get the length of the currencyState

        nextOffset = readerLen.offset;

        for (uint i = 0; i < readerLen.value; i++)
        {
           bridgeLaunched = bridgeLaunched | deserializeCoinbaseCurrencyState(notarization, nextOffset);
        }

        packedPositions |= uint64(bridgeLaunched << 16);

        readerLen = verusSerializer.readCompactSizeLE(notarization, nextOffset);    // get the length of proofroot array

        staterootposition = deserializeProofRoots(notarization, readerLen.value, nextOffset);

        packedPositions |= (uint64(staterootposition) << 32);

        return (packedPositions, prevnotarizationtxid, hashprevcrossnotarization);
    }

    function deserializeCoinbaseCurrencyState(bytes memory notarization, uint32 nextOffset) private view returns (uint16)
    {
        
        address currencyid;
        uint16 bridgeLaunched;
        uint16 flags;
        
        assembly {
            nextOffset := add(nextOffset, CURRENCY_LENGTH) // skip currencyid
            currencyid := mload(add(notarization, nextOffset))      // currencyid 
            nextOffset := add(nextOffset, 2) // skip version
            nextOffset := add(nextOffset, 2) // move to flags
            flags := mload(add(notarization, nextOffset))      // flags 
        }
        flags = (flags >> 8) | (flags << 8);
        if ((currencyid == VerusConstants.VerusBridgeAddress) && flags & (FLAG_FRACTIONAL + FLAG_REFUNDING + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER) == 
            (FLAG_FRACTIONAL + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER)) 
        {
            bridgeLaunched = 1;
        }
        assembly {                    
                    nextOffset := add(nextOffset, CURRENCY_LENGTH) //skip notarization currencystatecurrencyid
                 }
        
        VerusObjectsCommon.UintReader memory readerLen;
        readerLen = verusSerializer.readCompactSizeLE(notarization, nextOffset);        // get the length currencies

        nextOffset = nextOffset + (readerLen.value * BYTES32_LENGTH) + 2;       // currencys, wights, reserves arrarys

        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the initialsupply
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the emitted
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the supply

        assembly {
                    nextOffset := add(nextOffset, BYTES32_LENGTH) //skip coinbasecurrencystate first 4 items fixed at 4 x 8
                }

        readerLen = verusSerializer.readCompactSizeLE(notarization, nextOffset);    // get the length of the reservein array of uint64
        nextOffset = readerLen.offset + (readerLen.value * 60) + 7;                 //skip 60 bytes of rest of state knowing array size always same as first

        return bridgeLaunched;
    }

    function deserializeProofRoots (bytes memory notarization, uint32 size, uint32 nextOffset) private pure returns (uint32 outputPosition)
    {
        for (uint i = 0; i < size; i++)
        {
            uint16 proofType;
            address systemID;
            bytes32 tempStateRoot;
            assembly {
                nextOffset := add(nextOffset, CURRENCY_LENGTH) // skip systemid
                nextOffset := add(nextOffset, 2) // skip version
                nextOffset := add(nextOffset, 2) // move to read type
                proofType := mload(add(notarization, nextOffset))      // proofType 
                nextOffset := add(nextOffset, CURRENCY_LENGTH) // move to read systemID
                systemID := mload(add(notarization, nextOffset))  
                nextOffset := add(nextOffset, 4) // skip height
                nextOffset := add(nextOffset, BYTES32_LENGTH) // move to read stateroot
                tempStateRoot := mload(add(notarization, nextOffset))  
                nextOffset := add(nextOffset, TWO2BYTES32_LENGTH) // skip blockhash + power
            }
            if(systemID == VerusConstants.VEth)
            {
                outputPosition = nextOffset - TWO2BYTES32_LENGTH;
            }
            if((proofType >> 8) == 2){
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
            return VerusObjectsCommon.UintReader(uint32(v), uint32(idx + i + 1));
        }
        revert(); // i=9, invalid varint stream
    }
    
}


