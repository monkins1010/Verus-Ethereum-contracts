// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;
import "../Libraries/VerusObjects.sol";

import "../Libraries/VerusObjectsCommon.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Storage/StorageMaster.sol";

contract NotarizationSerializer is VerusStorage {

    address immutable VETH;
    address immutable BRIDGE;
    address immutable VERUS;
    address immutable DAI;

    constructor(address vETH, address Bridge, address Verus, address Dai){

        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
        DAI = Dai;
    }

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
    uint8 constant UINT64_BYTES_SIZE = 8;

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

    function deserializeNotarization(bytes memory notarization) external returns (bytes32 proposerAndLaunched, 
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
        //position 0 of the rolling vote is use to determine whether votes have started
        else if (rollingVoteIndex != 0){
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
                    nextOffset := add(nextOffset, 1) //move to read length of notarizationcurrencystate
                }

        readerLen = readCompactSizeLE(notarization, nextOffset);    // get the length of the currencyState

        nextOffset = readerLen.offset - 1;   //readCompactSizeLE returns offset of next byte so move back to start of currencyState

        for (uint i = 0; i < readerLen.value; i++)
        {
            uint16 temp; // store the currency state flags
            (temp, nextOffset) = deserializeCoinbaseCurrencyState(notarization, nextOffset);
            bridgeConverterLaunched |= temp;
        }
        
        proposerAndLaunched = bytes32(uint256(proposerMain));
       
        if (!bridgeConverterActive && bridgeConverterLaunched > 0) {
                proposerAndLaunched |= bytes32(uint256(bridgeConverterLaunched) << VerusConstants.UINT176_BITS_SIZE);  // Shift 16bit value 22 bytes to pack in bytes32
        }

        nextOffset++; //move forwards to read le
        readerLen = readCompactSizeLE(notarization, nextOffset);    // get the length of proofroot array

        (stateRoot, blockHash, height) = deserializeProofRoots(notarization, uint32(readerLen.value), nextOffset);
    }

    function deserializeCoinbaseCurrencyState(bytes memory notarization, uint32 nextOffset) private returns (uint16, uint32)
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
        if ((currencyid == BRIDGE) && flags & (FLAG_FRACTIONAL + FLAG_REFUNDING + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER) == 
            (FLAG_FRACTIONAL + FLAG_LAUNCHCONFIRMED + FLAG_LAUNCHCOMPLETEMARKER)) 
        {
            bridgeLaunched = 1;
        }
        assembly {                    
                    
                    nextOffset := add(nextOffset, 1) // move to  read currency state length
        }
        VerusObjectsCommon.UintReader memory readerLen;

        readerLen = readCompactSizeLE(notarization, nextOffset);        // get the length currencies

        // reserves[2] contain the scaled reserve amounts for ETH and DAI
        uint daiToEthRatio;
        if (currencyid == BRIDGE) {
            daiToEthRatio = storeDAIConversionrate(notarization, nextOffset, uint8(readerLen.value));
        }

        if (bridgeConverterActive) {
            //NOTE: to convert ETH to DAI ratio we do reserves[0]DAI / reserves[1]ETH
            claimableFees[bytes32(uint256(uint160(VerusConstants.VDXF_ETH_TO_DAI_CONVERSION_RATIO)))] = daiToEthRatio; //store the fees in the notaryFeePool
        }
        nextOffset = nextOffset + (uint32(readerLen.value) * BYTES32_LENGTH) + 2;  

        readerLen = readVarintStruct(notarization, nextOffset);        // get the length of the initialsupply
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the emitted
        readerLen = readVarintStruct(notarization, readerLen.offset);        // get the length of the supply
        nextOffset = readerLen.offset;
        assembly {
                    nextOffset := add(nextOffset, 33) //skip coinbasecurrencystate first 4 items fixed at 4 x 8
                }

        readerLen = readCompactSizeLE(notarization, nextOffset);    // get the length of the reservein array of uint64
        nextOffset = readerLen.offset + (uint32(readerLen.value) * 60) + 6;     //skip 60 bytes of rest of state knowing array size always same as first

        return (bridgeLaunched, nextOffset);
    }

    function storeDAIConversionrate (bytes memory notarization, uint32 nextOffset, uint8 currenciesLen) private view returns (uint) {
        
        uint8 ethIndex;
        uint8 daiIndex;
        for (uint8 i = 0; i < currenciesLen; i++)
        {
            address currency;
            assembly {
                    nextOffset := add(nextOffset, CURRENCY_LENGTH) // move to  read currency length
                    currency := mload(add(notarization, nextOffset)) // move to  read currencyid
                }
            if (currency == VETH)
            {
               ethIndex = i;
            }
            if (currency == DAI)
            {
               daiIndex = i;
            }
        }

        //Skip the weights
        nextOffset = nextOffset + 1 + (uint32(currenciesLen) * 4) + 1; //move to read len of reserves

        //read the reserves, position [0] for DAI, [1] for ETH
        uint[2] memory reserves;

        for (uint8 i = 0; i < currenciesLen; i++)
        {
            uint64 reserve;
            assembly {
                    nextOffset := add(nextOffset, UINT64_BYTES_SIZE) // move to  read currency length
                    reserve := mload(add(notarization, nextOffset)) // move to  read currencyid
                }
            if (i == daiIndex)
            {
               reserves[0] = serializeUint64(reserve);
            }
            else if (i == ethIndex)
            {
               reserves[1] = serializeUint64(reserve);
            }
        }

        assembly {                    
            nextOffset := add(nextOffset, 1) // move forward to read next varint.
        }

        //NOTE: to convert ETH to DAI ratio we do reserves[0]DAI / reserves[1]ETH

        uint256 ethToDaiRatio;
        
        if (reserves[0] > 0 && reserves[1] > 0)
         { 
            ethToDaiRatio = reserves[0] / reserves[1];
         }

        return ethToDaiRatio;  
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
            
            if(systemID == VERUS)
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
            rollingVoteIndex = 1; // use position 0 to determine whether votes have started
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

    function serializeUint64(uint64 v) public pure returns(uint64){
        
        v = ((v & 0xFF00FF00FF00FF00) >> 8) |
        ((v & 0x00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = (v >> 32) | (v << 32);
        return v;
    }
}


