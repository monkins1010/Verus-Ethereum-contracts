// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;
import "../Libraries/VerusObjects.sol";
import "./VerusBlake2b.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "../Libraries/VerusObjectsCommon.sol";

contract VerusProof {

    uint256 mmrRoot;
    VerusBlake2b blake2b;
    VerusNotarizer verusNotarizer;
    VerusSerializer verusSerializer;
    
    bytes32[] public computedValues;
    bytes32 public testHashedTransfers;
    bytes32 public txValue;
    bytes public testTransfers;
    bool public testResult;

    // these constants should be able to reference each other, as many are relative, but Solidity does not
    // allow referencing them and still considering the result a constant. For any changes to these constants,
    // which are designed to ensure smart transaction provability, care must be take to ensure that OUTPUT_SCRIPT_OFFSET
    // is present and substituted for all equivalent values (currently (32 + 8))
    uint8 constant CCE_EVAL_EXPORT = 0xc;
    uint32 constant CCE_COPTP_HEADERSIZE = 0x1c;
    uint32 constant CCE_COPTP_EVALOFFSET = 2;
    uint32 constant CCE_SOURCE_SYSTEM_OFFSET = (4 + 19);
    uint32 constant CCE_HASH_TRANSFERS_DELTA = 32;
    uint32 constant CCE_DEST_SYSTEM_DELTA = 20;
    uint32 constant CCE_DEST_CURRENCY_DELTA = 20;

    uint32 constant OUTPUT_SCRIPT_OFFSET = (8 + 1);                 // start of prevector serialization for output script
    uint32 constant SCRIPT_OP_CHECKCRYPTOCONDITION = 0xcc;
    uint32 constant SCRIPT_OP_PUSHDATA1 = 0x4c;
    uint32 constant SCRIPT_OP_PUSHDATA2 = 0x4d;
    uint32 constant TYPE_TX_OUTPUT = 4;

    event HashEvent(bytes32 newHash,uint8 eventType);

    constructor(address notarizerAddress,address verusBLAKE2b,address verusSerializerAddress) {
        blake2b = VerusBlake2b(verusBLAKE2b);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        verusNotarizer = VerusNotarizer(notarizerAddress);   
    }

    function hashTransfers(VerusObjects.CReserveTransfer[] memory _transfers) public view returns (bytes32){
        bytes memory sTransfers = verusSerializer.serializeCReserveTransfers(_transfers, false);
        return keccak256(sTransfers);
    }

    function checkProof(bytes32 hashToProve, VerusObjects.CTXProof[] memory _branches) public view returns(bytes32){
        //loop through the branches from bottom to top
        bytes32 hashInProgress = hashToProve;
        for(uint i = 0; i < _branches.length; i++){
            hashInProgress = checkBranch(hashInProgress,_branches[i].proofSequence);
        }
        return hashInProgress;
    }

    function checkBranch(bytes32 _hashToCheck,VerusObjects.CMerkleBranch memory _branch) public view returns(bytes32){
        
        require(_branch.nIndex >= 0,"Index cannot be less than 0");
        require(_branch.branch.length > 0,"Branch must be longer than 0");
        uint branchLength = _branch.branch.length;
        bytes32 hashInProgress = _hashToCheck;
        bytes memory joined;
        //hashInProgress = blake2b.bytesToBytes32(abi.encodePacked(_hashToCheck));
        uint hashIndex = _branch.nIndex;
        
       for(uint i = 0;i < branchLength; i++){
            if(hashIndex & 1 > 0){
                require(_branch.branch[i] != _hashToCheck,"Value can be equal to node but never on the right");
                //join the two arrays and pass to blake2b
                joined = abi.encodePacked(_branch.branch[i],hashInProgress);
            } else {
                joined = abi.encodePacked(hashInProgress,_branch.branch[i]);
            }
            hashInProgress = blake2b.createHash(joined);
            hashIndex >>= 1;
        }

        return hashInProgress;

    }
    
    function checkTransfers(VerusObjects.CReserveTransferImport memory _import) public view returns (bool) {

        // ensure that the hashed transfers are in the export
        bytes32 hashedTransfers = hashTransfers(_import.transfers);

        // the first component of the import partial transaction proof is the transaction header, for each version of
        // transaction header, we have a specific offset for the hash of transfers. if we change this, we must
        // deprecate and deploy new contracts
        uint doneLen = _import.partialtransactionproof.components.length;
        uint i;

        for (i = 1; i < doneLen; i++)
        {
            if (_import.partialtransactionproof.components[i].elType == TYPE_TX_OUTPUT)
            {
                bytes memory firstObj = _import.partialtransactionproof.components[i].elVchObj; // we should have a first entry that is the txout with the export

                // ensure this is an export to VETH and pull the hash for reserve transfers
                // to ensure a valid export.
                // the eval code for the main COptCCParams must be EVAL_CROSSCHAIN_EXPORT, and the destination system
                // must match VETH

                uint32 nextOffset;
                uint8 opCode1;
                uint8 opCode2;
                VerusObjectsCommon.UintReader memory readerLen;

                readerLen = verusSerializer.readCompactSizeLE(firstObj, OUTPUT_SCRIPT_OFFSET);    // get the length of the output script
                readerLen = verusSerializer.readCompactSizeLE(firstObj, readerLen.offset);        // then length of first master push

                // must be push less than 75 bytes, as that is an op code encoded similarly to a vector.
                // all we do here is ensure that is the case and skip master
                if (readerLen.value == 0 || readerLen.value > 0x4b)
                {
                    return false;
                }

                nextOffset = readerLen.offset + readerLen.value;        // add the length of the push of master to point to cc opcode

                assembly {
                    opCode1 := mload(add(firstObj, nextOffset))         // this should be OP_CHECKCRYPTOCONDITION
                    nextOffset := add(nextOffset, 1)                    // and after that...
                    opCode2 := mload(add(firstObj, nextOffset))         // should be OP_PUSHDATA1 or OP_PUSHDATA2
                    nextOffset := add(nextOffset, 1)                    // point to the length of the pushed data after CC instruction
                }

                if (opCode1 != SCRIPT_OP_CHECKCRYPTOCONDITION ||
                    (opCode2 != SCRIPT_OP_PUSHDATA1 && opCode2 != SCRIPT_OP_PUSHDATA2))
                {
                    return false;
                }

                uint16 optCCParamLen;
                if (opCode2 == SCRIPT_OP_PUSHDATA1)
                {
                    uint8 tempUi8;
                    assembly {
                        tempUi8 := mload(add(firstObj, nextOffset))     // single byte val
                        nextOffset := add(nextOffset, 1)
                    }
                    optCCParamLen = tempUi8;
                }
                else
                {
                    uint8 tempUi8lo;
                    uint8 tempUi8hi;
                    assembly {
                        tempUi8lo := mload(add(firstObj, nextOffset))    // first LE byte val
                        nextOffset := add(nextOffset, 1)
                        tempUi8hi := mload(add(firstObj, nextOffset))    // second LE byte val
                        nextOffset := add(nextOffset, 1)
                    }
                    optCCParamLen = tempUi8hi;
                    optCCParamLen = (optCCParamLen << 8) + tempUi8lo;
                }

                // COptCCParams are serialized as pushes in a script, first the header, then the keys, then the data
                // skip right to the serialized export and then to the source system
                uint8 evalCode;
                nextOffset += CCE_COPTP_EVALOFFSET;
                assembly {
                    evalCode := mload(add(firstObj, nextOffset))
                }

                if (evalCode != CCE_EVAL_EXPORT)
                {
                    return false;
                }

                nextOffset = nextOffset + (CCE_COPTP_HEADERSIZE - CCE_COPTP_EVALOFFSET) + CCE_SOURCE_SYSTEM_OFFSET;

                bytes32 incomingValue;
                address systemSourceID;
                address destSystemID;
                address destCurrencyID;

                assembly {
                    systemSourceID := mload(add(firstObj, nextOffset))      // source system ID, which should match expected source (VRSC/VRSCTEST)
                    nextOffset := add(nextOffset, CCE_HASH_TRANSFERS_DELTA)
                    incomingValue := mload(add(firstObj, nextOffset))       // get hash of reserve transfers from partial transaction proof
                    nextOffset := add(nextOffset, CCE_DEST_SYSTEM_DELTA)
                    destSystemID := mload(add(firstObj, nextOffset))        // destination system, which should be vETH
                    nextOffset := add(nextOffset, CCE_DEST_CURRENCY_DELTA)
                    destCurrencyID := mload(add(firstObj, nextOffset))      // destination currency, which should be vETH
                }

                // validate source and destination values as well
                return (hashedTransfers == incomingValue &&
                        systemSourceID == VerusConstants.VerusSystemId &&
                        destSystemID == VerusConstants.EthSystemID &&
                        destCurrencyID == VerusConstants.VEth);
            }
        }
        return false;
    }

    // roll through each proveComponents
    function proveComponents(VerusObjects.CReserveTransferImport memory _import) public view returns(bytes32 txRoot){
        //delete computedValues
        bytes32 hashInProgress;
        bytes32 testHash;

        if (_import.partialtransactionproof.components.length > 0)
        {   
            hashInProgress = blake2b.createHash(_import.partialtransactionproof.components[0].elVchObj);
            if (_import.partialtransactionproof.components[0].elType == 1 )
            {
                txRoot = checkProof(hashInProgress,_import.partialtransactionproof.components[0].elProof);           
            }
        }

        for (uint i = 1; i < _import.partialtransactionproof.components.length; i++) {
            hashInProgress = blake2b.createHash(_import.partialtransactionproof.components[i].elVchObj);
            testHash = checkProof(hashInProgress,_import.partialtransactionproof.components[i].elProof);
        
            if (txRoot != testHash) {
                txRoot = 0x0000000000000000000000000000000000000000000000000000000000000000;
                break;
            }
        }

        return txRoot;
    }
    
    function proveTransaction(VerusObjects.CReserveTransferImport memory _import) public view returns(bytes32 stateRoot){
        stateRoot = 0x000000000000000000000000000000000000000000000000000000000000000;
        if(!checkTransfers(_import)) return stateRoot;
        
        bytes32 txRoot = proveComponents(_import);
        if(txRoot == 0x0000000000000000000000000000000000000000000000000000000000000000) return stateRoot;
        
        stateRoot = checkProof(txRoot,_import.partialtransactionproof.txproof);
        return stateRoot;
    }
    
    function proveImports(VerusObjects.CReserveTransferImport memory _import) public view returns(bool){
        bytes32 predictedRootHash;
        predictedRootHash = proveTransaction(_import);
        uint32 lastBlockHeight = verusNotarizer.lastBlockHeight();
        bytes32 predictedStateRoot = flipBytes32(verusNotarizer.notarizedStateRoots(lastBlockHeight));
        if(predictedRootHash == predictedStateRoot) {
            return true;
        } else return false;
    }

    /*
    function proveTransaction(bytes32 mmrRootHash,bytes32 notarisationHash,bytes32[] memory _transfersProof,uint32 _hashIndex) public view returns(bool){
        if (mmrRootHash == predictedRootHash(notarisationHash,_hashIndex,_transfersProof)) return true;
        else return false;
    }

    function predictedRootHash(bytes32 _hashToCheck,uint _hashIndex,bytes32[] memory _branch) public view returns(bytes32){
        
        require(_hashIndex >= 0,"Index cannot be less than 0");
        require(_branch.length > 0,"Branch must be longer than 0");
        uint branchLength = _branch.length;
        bytes32 hashInProgress;
        bytes memory joined;
        hashInProgress = blake2b.bytesToBytes32(abi.encodePacked(_hashToCheck));

       for(uint i = 0;i < branchLength; i++){
            if(_hashIndex & 1 > 0){
                require(_branch[i] != _hashToCheck,"Value can be equal to node but never on the right");
                //join the two arrays and pass to blake2b
                joined = abi.encodePacked(_branch[i],hashInProgress);
            } else {
                joined = abi.encodePacked(hashInProgress,_branch[i]);
            }
            hashInProgress = blake2b.createHash(joined);
            _hashIndex >>= 1;
        }

        return hashInProgress;

    }

    function checkHashInRoot(bytes32 _mmrRoot,bytes32 _hashToCheck,uint _hashIndex,bytes32[] memory _branch) public view returns(bool){
        bytes32 calculatedHash = predictedRootHash(_hashToCheck,_hashIndex,_branch);
        if(_mmrRoot == calculatedHash) return true;
        else return false;
    }*/
    
    function flipBytes32(bytes32 input) public pure returns (bytes32){
        return bytes32(reverseuint256(uint256(input)));
    }
    
    function reverseuint256(uint256 input) internal pure returns (uint256 v) {
        v = input;
    
        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);
    
        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);
    
        // swap 4-byte long pairs
        v = ((v & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32) |
            ((v & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);
    
        // swap 8-byte long pairs
        v = ((v & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64) |
            ((v & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);
    
        // swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
    }
    
    function slice(bytes memory _bytes,uint256 _start,uint256 _length
    )
        internal
        pure
        returns (bytes memory)
    {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }
    
}


