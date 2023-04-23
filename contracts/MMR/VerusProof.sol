// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0;
pragma abicoder v2;
import "../Libraries/VerusObjects.sol";
import "./VerusBlake2b.sol";
import {VerusSerializer} from "../VerusBridge/VerusSerializer.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusMMR.sol";
import "../Storage/StorageMaster.sol";

contract VerusProof is VerusStorage  {

    using VerusBlake2b for bytes;
    
    // these constants should be able to reference each other, as many are relative, but Solidity does not
    // allow referencing them and still considering the result a constant. For any changes to these constants,
    // which are designed to ensure smart transaction provability, care must be take to ensure that OUTPUT_SCRIPT_OFFSET
    // is present and substituted for all equivalent values (currently (32 + 8))
    uint8 constant CCE_EVAL_EXPORT = 0xc;
    uint32 constant CCE_COPTP_HEADERSIZE = 24 + 1;
    uint32 constant CCE_COPTP_EVALOFFSET = 2;
    uint32 constant CCE_SOURCE_SYSTEM_OFFSET = 24;
    uint32 constant CCE_HASH_TRANSFERS_DELTA = 32;
    uint32 constant CCE_DEST_SYSTEM_DELTA = 20;
    uint32 constant CCE_DEST_CURRENCY_DELTA = 20;

    uint32 constant OUTPUT_SCRIPT_OFFSET = (8 + 1);                 // start of prevector serialization for output script
    uint32 constant SCRIPT_OP_CHECKCRYPTOCONDITION = 0xcc;
    uint32 constant SCRIPT_OP_PUSHDATA1 = 0x4c;
    uint32 constant SCRIPT_OP_PUSHDATA2 = 0x4d;
    uint32 constant TYPE_TX_OUTPUT = 4;
    uint32 constant SIZEOF_UINT64 = 8;
    uint8 constant FLAG_FRACTIONAL = 1;
    uint8 constant FLAG_REFUNDING = 4;
    uint8 constant FLAG_LAUNCHCONFIRMED = 0x10;
    uint8 constant FLAG_LAUNCHCOMPLETEMARKER = 0x20;
    uint8 constant AUX_DEST_ETH_VEC_LENGTH = 22;


    function checkProof(bytes32 hashToProve, VerusObjects.CTXProof[] memory _branches) public view returns(bytes32){
        //loop through the branches from bottom to top
        bytes32 hashInProgress = hashToProve;
        for(uint i = 0; i < _branches.length; i++){
            hashInProgress = checkBranch(hashInProgress,_branches[i].proofSequence);
        }
        return hashInProgress;
    }

    function checkBranch(bytes32 _hashToCheck,VerusObjects.CMerkleBranch memory _branch) public view returns(bytes32){
        
        require(_branch.branch.length > 0,"Branch must be longer than 0");
        uint branchLength = _branch.branch.length;
        bytes32 hashInProgress = _hashToCheck;
        bytes memory joined;
        //hashInProgress = blake2b.bytesToBytes32(abi.encodePacked(_hashToCheck));

        uint hashIndex = VerusMMR.GetMMRProofIndex(_branch.nIndex, _branch.nSize, _branch.extraHashes);
        
       for(uint i = 0;i < branchLength; i++){
            if(hashIndex & 1 > 0){
                require(_branch.branch[i] != _hashToCheck,"Value can be equal to node but never on the right");
                //join the two arrays and pass to blake2b
                joined = abi.encodePacked(_branch.branch[i],hashInProgress);
            } else {
                joined = abi.encodePacked(hashInProgress,_branch.branch[i]);
            }
            hashInProgress = joined.createHash();
            hashIndex >>= 1;
        }

        return hashInProgress;

    }
    
    function checkTransfers(VerusObjects.CReserveTransferImport memory _import, bytes32 hashedTransfers) public view returns (uint64, uint128) {

        // the first component of the import partial transaction proof is the transaction header, for each version of
        // transaction header, we have a specific offset for the hash of transfers. if we change this, we must
        // deprecate and deploy new contracts

        for (uint i = 1; i < _import.partialtransactionproof.components.length; i++)
        {
            if (_import.partialtransactionproof.components[i].elType != TYPE_TX_OUTPUT)
                continue;
            
            bytes memory firstObj = _import.partialtransactionproof.components[i].elVchObj; // we should have a first entry that is the txout with the export

            // ensure this is an export to VETH and pull the hash for reserve transfers
            // to ensure a valid export.
            // the eval code for the main COptCCParams must be EVAL_CROSSCHAIN_EXPORT, and the destination system
            // must match VETH

            uint32 nextOffset;
            uint8 var1;
            uint8 opCode2;
            uint32 nIndex; 
            nIndex = _import.partialtransactionproof.components[i].elProof[0].proofSequence.nIndex;

            VerusObjectsCommon.UintReader memory readerLen;

            readerLen = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).readCompactSizeLE(firstObj, OUTPUT_SCRIPT_OFFSET);    // get the length of the output script
            readerLen = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).readCompactSizeLE(firstObj, readerLen.offset);        // then length of first master push

            // must be push less than 75 bytes, as that is an op code encoded similarly to a vector.
            // all we do here is ensure that is the case and skip master
            if (readerLen.value == 0 || readerLen.value > 0x4b)
            {
                return (uint64(0), uint128(0));
            }

            nextOffset = uint32(readerLen.offset + readerLen.value);        // add the length of the push of master to point to cc opcode

            assembly {
                var1 := mload(add(firstObj, nextOffset))         // this should be OP_CHECKCRYPTOCONDITION
                nextOffset := add(nextOffset, 1)                    // and after that...
                opCode2 := mload(add(firstObj, nextOffset))         // should be OP_PUSHDATA1 or OP_PUSHDATA2
                nextOffset := add(nextOffset, 1)                    // point to the length of the pushed data after CC instruction
            }

            if (var1 != SCRIPT_OP_CHECKCRYPTOCONDITION ||
                (opCode2 != SCRIPT_OP_PUSHDATA1 && opCode2 != SCRIPT_OP_PUSHDATA2))
            {
                return (uint64(0), uint128(0));
            }

            if (opCode2 == SCRIPT_OP_PUSHDATA1)
            {
                assembly {
                    nextOffset := add(nextOffset, 1)
                }
            }
            else
            {
                assembly {
                    nextOffset := add(nextOffset, 2)
                }

            }

            // COptCCParams are serialized as pushes in a script, first the header, then the keys, then the data
            // skip right to the serialized export and then to the source system

            nextOffset += CCE_COPTP_EVALOFFSET;
            assembly {
                var1 := mload(add(firstObj, nextOffset))
            }

            if (var1 != CCE_EVAL_EXPORT)
            {
                return (uint64(0), uint128(0));
            }

            nextOffset += CCE_SOURCE_SYSTEM_OFFSET;

            assembly {
                opCode2 := mload(add(firstObj, nextOffset))         // should be OP_PUSHDATA1 or OP_PUSHDATA2
            }

            nextOffset += CCE_COPTP_HEADERSIZE;
            
            if (opCode2 == SCRIPT_OP_PUSHDATA2)
            {
                    nextOffset += 1; // one extra byte taken for varint
            } 
           
            // validate source and destination values as well and set reward address
            return (checkCCEValues(firstObj, nextOffset, hashedTransfers, nIndex));
        
        }
        return (uint64(0), uint128(0));
    }

    function checkCCEValues(bytes memory firstObj, uint32 nextOffset, bytes32 hashedTransfers, uint32 nIndex) public view returns(uint64, uint128)
    {
        bytes32 hashReserveTransfers;
        address systemSourceID;
        address destSystemID;
        uint64 rewardFees;
        uint32 tempRegister;
        uint8 tmpuint8;
        uint128 packedRegister; //uint128(startheight) | (uint128(endheight) << 32) | (uint128(nIndex) << 64) | (uint128(numInputs) << 96));
        
        assembly {
            systemSourceID := mload(add(firstObj, nextOffset))      // source system ID, which should match expected source (VRSC/VRSCTEST)
            nextOffset := add(nextOffset, CCE_HASH_TRANSFERS_DELTA)
            hashReserveTransfers := mload(add(firstObj, nextOffset))// get hash of reserve transfers from partial transaction proof
            nextOffset := add(nextOffset, CCE_DEST_SYSTEM_DELTA)
            destSystemID := mload(add(firstObj, nextOffset))        // destination system, which should be vETH
            nextOffset := add(nextOffset, CCE_DEST_CURRENCY_DELTA)  // goto destcurrencyid
            nextOffset := add(nextOffset, 1)                        // goto exporter type  
            tmpuint8 := mload(add(firstObj, nextOffset))            // read exporter type
            nextOffset := add(nextOffset, 1)                        // goto exporter vec length
            nextOffset := add(nextOffset, CCE_DEST_CURRENCY_DELTA)  // goto exporter
        }

        if (tmpuint8 & VerusConstants.FLAG_DEST_AUX == VerusConstants.FLAG_DEST_AUX)
        {
            nextOffset += 1;  // goto auxdest parent vec length position
            (nextOffset, ) = skipAux(firstObj, nextOffset);
            nextOffset -= 1;  // NOTE: Next Varint call takes array pos not array pos +1
        }

        assembly {
            nextOffset := add(nextOffset, 8)                                // move to read num inputs
            tempRegister := mload(add(firstObj, nextOffset))                // number of numInputs                 
        }

        (packedRegister, nextOffset)  = readVarint(firstObj, nextOffset);   // put startheight at [0] 32bit chunk
        tempRegister = serializeUint32(tempRegister);       // reverse endian of no. transfers
        packedRegister  |= (uint128(tempRegister) << 96) ;                  // put number of transfers at [3] 32-bit chunk     
        
        (tempRegister, nextOffset)  = readVarint(firstObj, nextOffset); 
        packedRegister  |= (uint128(tempRegister) << 32) ;                  // put endheight at [1] 32 bit chunk
        packedRegister  |= (uint128(nIndex) << 64) ;                        // put nindex at [2] 32 bit chunk
        assembly {
            nextOffset := add(nextOffset, 1)                                // move to next byte for mapsize
            tmpuint8 := mload(add(firstObj, nextOffset)) 
        }

        if (tmpuint8 == 1) 
        {
            assembly {
                nextOffset := add(add(nextOffset, CCE_DEST_CURRENCY_DELTA), 8)  // move 20 + 8 bytes for (address + 64bit)
                rewardFees := mload(add(firstObj, nextOffset))    
            }
                rewardFees = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).serializeUint64(rewardFees);
        }

        if (!(hashedTransfers == hashReserveTransfers &&
                systemSourceID == VerusConstants.VerusSystemId &&
                destSystemID == VerusConstants.VEth)) {

            revert("CCE information does not checkout");
        }

        return (rewardFees, packedRegister); //uint128(startheight) | (uint128(endheight) << 32) | (uint128(nIndex) << 64) | (uint128(numInputs) << 96));

    }

    function skipAux (bytes memory firstObj, uint32 nextOffset) public view returns (uint32, uint176 auxDest)
    {
                                                  
            VerusObjectsCommon.UintReader memory readerLen;
            readerLen = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).readCompactSizeLE(firstObj, nextOffset);    // get the length of the auxDest
            nextOffset = readerLen.offset;
            uint arraySize = readerLen.value;
            
            for (uint i = 0; i < arraySize; i++)
            {
                    readerLen = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).readCompactSizeLE(firstObj, nextOffset);    // get the length of the auxDest sub array
                    if (readerLen.value == AUX_DEST_ETH_VEC_LENGTH)
                    {
                         assembly {
                            auxDest := mload(add(add(firstObj, nextOffset),AUX_DEST_ETH_VEC_LENGTH))
                         }
                    }

                    nextOffset = (readerLen.offset + uint32(readerLen.value));
            }
            return (nextOffset, auxDest);
    }

    // roll through each proveComponents
    function proveComponents(VerusObjects.CReserveTransferImport memory _import) public view returns(bytes32 txRoot){
     
        bytes32 hashInProgress;
        bytes32 testHash;
  
        hashInProgress = _import.partialtransactionproof.components[0].elVchObj.createHash();
        if (_import.partialtransactionproof.components[0].elType == 1 )
        {
            txRoot = checkProof(hashInProgress, _import.partialtransactionproof.components[0].elProof);           
        }
        
        for (uint i = 1; i < _import.partialtransactionproof.components.length; i++) {

            hashInProgress = _import.partialtransactionproof.components[i].elVchObj.createHash();
            testHash = checkProof(hashInProgress, _import.partialtransactionproof.components[i].elProof);
        
            if (txRoot != testHash) 
            {
                txRoot = bytes32(0);
                break;
            }
        }

        return txRoot;
    }
    
    function proveImports(bytes calldata dataIn ) external view returns(uint64, uint128){
        
        (VerusObjects.CReserveTransferImport memory _import, bytes32 hashOfTransfers) = abi.decode(dataIn, (VerusObjects.CReserveTransferImport, bytes32));
        bytes32 confirmedStateRoot;
        bytes32 retStateRoot;
        uint64 fees;
        uint128 heightsAndTXNum;

        (fees, heightsAndTXNum) = checkTransfers(_import, hashOfTransfers);
        
        bytes32 txRoot = proveComponents(_import);

        if(txRoot == bytes32(0))
        { 
            revert("Components do not validate"); 
        }

        retStateRoot = checkProof(txRoot, _import.partialtransactionproof.txproof);
        confirmedStateRoot = getLastConfirmedVRSCStateRoot();

        if (retStateRoot == bytes32(0) || retStateRoot != confirmedStateRoot) {

            revert("Stateroot does not match");
        }
        //truncate to only return heights as, contract will revert if issue with proofs.
        return (fees, heightsAndTXNum);
 
    }

    function getLastConfirmedVRSCStateRoot() public view returns (bytes32) {

        bytes32 stateRoot;
        bytes32 slotHash;
        bytes storage tempArray = bestForks[0];
        uint32 nextOffset;

        if (tempArray.length > 0)
        {
            bytes32 slot;
            assembly {
                        mstore(add(slot, 32),tempArray.slot)
                        slotHash := keccak256(add(slot, 32), 32)
                        nextOffset := add(nextOffset, 1)  
                        nextOffset := add(nextOffset, 1)  
                        stateRoot := sload(add(slotHash, nextOffset))
            }
        }

        return stateRoot;
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

    function getTokenList(uint256 start, uint256 end) external view returns(VerusObjects.setupToken[] memory ) {

        uint tokenListLength;
        tokenListLength = tokenList.length;
        VerusObjects.setupToken[] memory temp = new VerusObjects.setupToken[](tokenListLength);
        VerusObjects.mappedToken memory recordedToken;
        uint i;
        uint endPoint;

        endPoint = tokenListLength;
        if (start >= 0 && start < tokenListLength)
        {
            i = start;
        }

        if (end > i && end < tokenListLength)
        {
            endPoint = end;
        }

        for(; i < endPoint; i++) {

            address iAddress;
            iAddress = tokenList[i];
            recordedToken = verusToERC20mapping[iAddress];
            temp[i].iaddress = iAddress;
            temp[i].flags = recordedToken.flags;

            if (iAddress == VerusConstants.VEth)
            {
                temp[i].erc20ContractAddress = address(0);
                temp[i].name = "Testnet ETH";
                temp[i].ticker = "ETH";
            }
            else if(recordedToken.flags & VerusConstants.TOKEN_LAUNCH == VerusConstants.TOKEN_LAUNCH )
            {
                Token token = Token(recordedToken.erc20ContractAddress);
                temp[i].erc20ContractAddress = address(token);
                temp[i].name = recordedToken.name;
                temp[i].ticker = token.symbol();
            }
            else if(recordedToken.flags & VerusConstants.TOKEN_ETH_NFT_DEFINITION == VerusConstants.TOKEN_ETH_NFT_DEFINITION)
            {
                temp[i].erc20ContractAddress = recordedToken.erc20ContractAddress;
                temp[i].name = recordedToken.name;
                temp[i].tokenID = recordedToken.tokenID;
            }
            
        }

        return temp;
    }

    function serializeUint32(uint32 number) public pure returns(uint32){
        // swap bytes
        number = ((number & 0xFF00FF00) >> 8) | ((number & 0x00FF00FF) << 8);
        number = (number >> 16) | (number << 16);
        return number;
    }
    
}


