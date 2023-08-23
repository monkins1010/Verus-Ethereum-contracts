// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;
import "../Libraries/VerusObjects.sol";

import "../Libraries/VerusObjectsCommon.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Storage/StorageMaster.sol";

contract NotarizationSerializer is VerusStorage {

    uint8 constant CURRENCY_LENGTH = 20;
    uint8 constant BYTES32_LENGTH = 32;
    uint8 constant TWO2BYTES32_LENGTH = 64;
    uint8 constant FLAG_FRACTIONAL = 1;
    uint8 constant FLAG_REFUNDING = 4;
    uint8 constant FLAG_LAUNCHCONFIRMED = 0x10;
    uint8 constant FLAG_LAUNCHCOMPLETEMARKER = 0x20;
    uint8 constant AUX_DEST_ETH_VEC_LENGTH = 22;
    uint8 constant AUX_DEST_VOTE_HASH = 21;
    uint8 constant VOTE_BYTE_POSITION = 22;
    uint8 constant REQUIREDAMOUNTOFVOTES = 100;
    uint8 constant WINNINGAMOUNT = 51;

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

    function deserializeNotarization(bytes memory notarization) public returns (bytes32 proposerAndLaunched, 
                                                                                    bytes32 prevnotarizationtxid, 
                                                                                    bytes32 hashprevcrossnotarization, 
                                                                                    bytes32 stateRoot, 
                                                                                    bytes32 blockHash, 
                                                                                    uint32 height) {
        
        uint32 nextOffset;
        uint16 bridgeConverterLaunched;
        uint8 proposerType;
        uint32 notarizationFlags;
        uint176 proposerMain;

        VerusObjectsCommon.UintReader memory readerLen;

        readerLen = readVarintStruct(notarization, 0);    // get the length of the varint version
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the flags

        notarizationFlags = uint32(readerLen.value);
        nextOffset = readerLen.offset;

        assembly {
                    nextOffset := add(nextOffset, 1)  // move to read type
                    proposerType := mload(add(nextOffset, notarization))
                    if gt(and(proposerType, 0xff), 0) {
                        nextOffset := add(nextOffset, 21) // move to proposer, type and vector length
                        proposerMain := mload(add(nextOffset, notarization))
                    }
                 }

        if (proposerType & VerusConstants.FLAG_DEST_AUX == VerusConstants.FLAG_DEST_AUX)
        {
            nextOffset += 1;  // goto auxdest parent vec length position
            nextOffset = processAux(notarization, nextOffset, notarizationFlags);
            nextOffset -= 1;  // NOTE: Next Varint call takes array pos not array pos +1
        }
        else {
            castVote(address(0));
        }

        assembly {
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

        readerLen = readCompactSizeLE(notarization, nextOffset);    // get the length of the currencyState

        nextOffset = readerLen.offset - 1;   //readCompactSizeLE returns 1 byte after and wants one byte after 

        for (uint i = 0; i < readerLen.value; i++)
        {
            uint16 temp;
            (temp, nextOffset) = deserializeCoinbaseCurrencyState(notarization, nextOffset);
            bridgeConverterLaunched = temp | bridgeConverterLaunched;
        }

        proposerAndLaunched = getProposerandLaunched(proposerMain, uint8(bridgeConverterLaunched));

        nextOffset++; //move forwards to read le
        readerLen = readCompactSizeLE(notarization, nextOffset);    // get the length of proofroot array

        (stateRoot, blockHash, height) = deserializeProofRoots(notarization, uint32(readerLen.value), nextOffset);

    }

    function getProposerandLaunched(uint176 proposerMain, uint8 bridgeConverterLaunched) private view returns (bytes32 proposerAndLaunched) {

       proposerAndLaunched = bytes32(uint256(proposerMain));
       
       // if the msg.sender is a valid notary then add their index in with the valid flag to a byte
       if(notaryAddressMapping[msg.sender].state == VerusConstants.NOTARY_VALID) {
            //pack in the notarizers ID and valid flag at the defined location, NOTE: the notarisers index can be [0].
            proposerAndLaunched |= bytes32(uint256(uint8(uint160(notaryAddressMapping[msg.sender].recovery)) // .recovery == to the index | 0x80
                                        | VerusConstants.GLOBAL_TYPE_NOTARY_VALID_HIGH_BIT) << VerusConstants.NOTARIZER_INDEX_AND_FLAGS_OFFSET);
        } 
        if (!bridgeConverterActive && bridgeConverterLaunched > 0) {
                proposerAndLaunched |= bytes32(uint256(bridgeConverterLaunched) << VerusConstants.UINT176_BITS_SIZE);  // Shift 16bit value 22 bytes to pack in bytes32
        }
    }

    function deserializeCoinbaseCurrencyState(bytes memory notarization, uint32 nextOffset) private pure returns (uint16, uint32)
    {
        address currencyid;
        uint16 bridgeLaunched;
        uint16 flags;
        
        assembly {
            nextOffset := add(nextOffset, 2) // move to version
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

        readerLen = readCompactSizeLE(notarization, nextOffset);        // get the length currencies

        nextOffset = nextOffset + (uint32(readerLen.value) * BYTES32_LENGTH) + 2;       // currencys, wights, reserves arrarys

        readerLen = readVarintStruct(notarization, nextOffset);        // get the length of the initialsupply
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the emitted
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the supply
        nextOffset = readerLen.offset;
        assembly {
                    nextOffset := add(nextOffset, 33) //skip coinbasecurrencystate first 4 items fixed at 4 x 8
                }

        readerLen = readCompactSizeLE(notarization, nextOffset);    // get the length of the reservein array of uint64
        nextOffset = readerLen.offset + (uint32(readerLen.value) * 60) + 6;                 //skip 60 bytes of rest of state knowing array size always same as first

        return (bridgeLaunched, nextOffset);
    }

    function deserializeProofRoots (bytes memory notarization, uint32 size, uint32 nextOffset) private pure returns (bytes32 stateRoot, bytes32 blockHash, uint32 height)
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
                nextOffset := add(nextOffset, BYTES32_LENGTH) // move to power
            }
            
            if(systemID == VerusConstants.VerusCurrencyId)
            {
                stateRoot = tempStateRoot;
                blockHash = tempBlockHash;
                height = serializeUint32(tempHeight); //swapendian
            }

            //swap 16bit endian
            if(((proofType >> 8) | (proofType << 8)) == 2){ //IF TYPE ETHEREUM TODO: add constant
                assembly {
                    nextOffset := add(nextOffset, 8) // move to gasprice
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
    
    function processAux (bytes memory firstObj, uint32 nextOffset, uint32 NotarizationFlags) private returns (uint32)
    {
                                                  
            VerusObjectsCommon.UintReader memory readerLen;
            readerLen = readCompactSizeLE(firstObj, nextOffset);    // get the length of the auxDest
            nextOffset = readerLen.offset;
            uint arraySize = readerLen.value;
            address tempAddress;
            
            for (uint i = 0; i < arraySize; i++)
            {
                    readerLen = readCompactSizeLE(firstObj, nextOffset);    // get the length of the auxDest sub array
                    assembly {
                        tempAddress := mload(add(add(firstObj, nextOffset),AUX_DEST_ETH_VEC_LENGTH))
                    }

                    castVote((NotarizationFlags & VerusConstants.FLAG_CONTRACT_UPGRADE > 0) ? tempAddress : address(0));
                    
                    nextOffset = (readerLen.offset + uint32(readerLen.value));
            }
            return nextOffset;
    }

    function castVote(address votetxid) private {

        rollingUpgradeVotes[rollingVoteIndex] = votetxid;
        if(rollingVoteIndex > 98) {
            rollingVoteIndex = 0;
        } else {
            rollingVoteIndex = rollingVoteIndex + 1;
        }

    }

    function readCompactSizeLE(bytes memory incoming, uint32 offset) public pure returns(VerusObjectsCommon.UintReader memory) {

        uint8 oneByte;
        assembly {
            oneByte := mload(add(incoming, offset))
        }
        offset++;
        if (oneByte < 253)
        {
            return VerusObjectsCommon.UintReader(offset, oneByte);
        }
        else if (oneByte == 253)
        {
            offset++;
            uint16 twoByte;
            assembly {
                twoByte := mload(add(incoming, offset))
            }
 
            return VerusObjectsCommon.UintReader(offset + 1, ((twoByte << 8) & 0xffff)  | twoByte >> 8);
        }
        return VerusObjectsCommon.UintReader(offset, 0);
    }

    function serializeUint32(uint32 number) public pure returns(uint32){
        // swap bytes
        number = ((number & 0xFF00FF00) >> 8) | ((number & 0x00FF00FF) << 8);
        number = (number >> 16) | (number << 16);
        return number;
    }
}


