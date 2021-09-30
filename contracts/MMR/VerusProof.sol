// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;
import "../Libraries/VerusObjects.sol";
import "./VerusBlake2b.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../VerusNotarizer/VerusNotarizer.sol";

contract VerusProof{

    uint256 mmrRoot;
    VerusBlake2b blake2b;
    VerusNotarizer verusNotarizer;
    VerusSerializer verusSerializer;
    
    bytes32[] public computedValues;
    bytes32 public testHashedTransfers;
    bytes32 public txValue;
    bytes public testTransfers;
    bool public testResult;
    
    event HashEvent(bytes32 newHash,uint8 eventType);

    constructor(address notarizerAddress,address verusBLAKE2b,address verusSerializerAddress) {
        blake2b = VerusBlake2b(verusBLAKE2b);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        verusNotarizer = VerusNotarizer(notarizerAddress);   
    }

    function hashTransfers(VerusObjects.CReserveTransfer[] memory _transfers) public view returns (bytes32){
        bytes memory sTransfers = verusSerializer.serializeCReserveTransfers(_transfers,false);
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
    
    function checkTransfers(VerusObjects.CReserveTransferImport memory _import) public view returns (bool){
        //identify if the hashed transfers are in the 
        bytes32 hashedTransfers = hashTransfers(_import.transfers);
        //check they occur in the last elVchObj
        uint transfersIndex = _import.partialtransactionproof.components[_import.partialtransactionproof.components.length -1].VchObjIndex;
        bytes memory toCheck = _import.partialtransactionproof.components[_import.partialtransactionproof.components.length -1].elVchObj;
        bytes32 incomingValue = blake2b.bytesToBytes32(slice(toCheck,transfersIndex,32));
        if(hashedTransfers == incomingValue) return true;
        else return false;
    }
    
    
    //roll through each proveComponents
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
        
        for(uint i = 1; i < _import.partialtransactionproof.components.length; i++){
            hashInProgress = blake2b.createHash(_import.partialtransactionproof.components[i].elVchObj);
            testHash = checkProof(hashInProgress,_import.partialtransactionproof.components[i].elProof);
        
           if(txRoot != testHash){
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


