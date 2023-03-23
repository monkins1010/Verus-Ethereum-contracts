// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0;
pragma abicoder v2;
import "../Libraries/VerusObjects.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../VerusBridge/UpgradeManager.sol";

contract NotarizationSerializer {

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

    function deserilizeNotarization(bytes memory notarization) public returns (bytes32 proposerAndLaunched, 
                                                                                    bytes32 prevnotarizationtxid, 
                                                                                    bytes32 hashprevcrossnotarization, 
                                                                                    bytes32 stateRoot, 
                                                                                    bytes32 blockHash, 
                                                                                    uint32 height) {
        
        uint32 nextOffset;
        uint16 bridgeLaunched;
        uint176 auxProposer;
        uint8 proposerFlags;

        VerusObjectsCommon.UintReader memory readerLen;

        readerLen = readVarintStruct(notarization, 0);    // get the length of the varint version
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the flags

        nextOffset = readerLen.offset;

        assembly {
                    nextOffset := add(nextOffset, 1)  // move to read type
                    proposerFlags := mload(add(nextOffset, notarization))
                    nextOffset := add(nextOffset, 21) // move to proposer, type and vector length
                    proposerAndLaunched := and(mload(add(nextOffset, notarization)), 0x00000000000000000000ffffffffffffffffffffffffffffffffffffffffffff)   // type+len+proposer 22bytes
                 }

        if (proposerFlags & VerusConstants.FLAG_DEST_AUX == VerusConstants.FLAG_DEST_AUX)
        {
            nextOffset += 1;  // goto auxdest parent vec length position
            (nextOffset, auxProposer) = processAux(notarization, nextOffset);
            nextOffset -= 1;  // NOTE: Next Varint call takes array pos not array pos +1
            proposerAndLaunched = bytes32(uint256(auxProposer));
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

        readerLen = VerusSerializer.readCompactSizeLE(notarization, nextOffset);    // get the length of the currencyState

        nextOffset = readerLen.offset - 1;   //readCompactSizeLE returns 1 byte after and wants one byte after 

        for (uint i = 0; i < readerLen.value; i++)
        {
            uint16 temp;
            (temp, nextOffset) = deserializeCoinbaseCurrencyState(notarization, nextOffset);
            bridgeLaunched = temp | bridgeLaunched;
        }

        proposerAndLaunched |= bytes32(uint256(bridgeLaunched) << 176);  // Shift 16bit value 22 bytes to pack in bytes32

        nextOffset++; //move forwards to read le
        readerLen = VerusSerializer.readCompactSizeLE(notarization, nextOffset);    // get the length of proofroot array

        (stateRoot, blockHash, height) = deserializeProofRoots(notarization, uint32(readerLen.value), nextOffset);

    }

    function deserializeCoinbaseCurrencyState(bytes memory notarization, uint32 nextOffset) private view returns (uint16, uint32)
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

        readerLen = VerusSerializer.readCompactSizeLE(notarization, nextOffset);        // get the length currencies

        nextOffset = nextOffset + (uint32(readerLen.value) * BYTES32_LENGTH) + 2;       // currencys, wights, reserves arrarys

        readerLen = readVarintStruct(notarization, nextOffset);        // get the length of the initialsupply
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the emitted
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the supply
        nextOffset = readerLen.offset;
        assembly {
                    nextOffset := add(nextOffset, 33) //skip coinbasecurrencystate first 4 items fixed at 4 x 8
                }

        readerLen = VerusSerializer.readCompactSizeLE(notarization, nextOffset);    // get the length of the reservein array of uint64
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
                nextOffset := add(nextOffset, BYTES32_LENGTH) // move to power
            }
            
            if(systemID == VerusConstants.VerusCurrencyId)
            {
                stateRoot = tempStateRoot;
                blockHash = tempBlockHash;
                height = VerusSerializer.serializeUint32(tempHeight); //swapendian
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
    
    function processAux (bytes memory firstObj, uint32 nextOffset) private returns (uint32, uint176 auxDest)
    {
                                                  
            VerusObjectsCommon.UintReader memory readerLen;
            readerLen = readCompactSizeLE(firstObj, nextOffset);    // get the length of the auxDest
            nextOffset = readerLen.offset;
            uint arraySize = readerLen.value;
            bytes32 voteHash;
            uint8 voteByte;
            
            for (uint i = 0; i < arraySize; i++)
            {
                    readerLen = readCompactSizeLE(firstObj, nextOffset);    // get the length of the auxDest sub array
                    if (i == 0 && readerLen.value == AUX_DEST_ETH_VEC_LENGTH)
                    {
                        assembly {
                            auxDest := mload(add(add(firstObj, nextOffset),AUX_DEST_ETH_VEC_LENGTH))
                        }
                    }
                    else if( i == 1 && readerLen.value == VOTE_BYTE_POSITION) {
                        assembly {
                            voteHash := mload(add(add(firstObj, nextOffset),AUX_DEST_VOTE_HASH))
                            voteByte := mload(add(add(firstObj, nextOffset),VOTE_BYTE_POSITION))
                        }
                        bool voted = (voteHash == verusUpgradeContract.newContractsPendingHash() && voteByte == 1);
                        verusUpgradeContract.updateVote(voted);
                    }

                    nextOffset = (readerLen.offset + uint32(readerLen.value));
            }
            return (nextOffset, auxDest);
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
}


