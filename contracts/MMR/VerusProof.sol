// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;
import "../Libraries/VerusObjects.sol";
import "./VerusBlake2b.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./MMR.sol";

contract VerusProof {

    uint256 mmrRoot;
    VerusSerializer verusSerializer;
    VerusNotarizer verusNotarizer;
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
    address verusUpgradeContract;

    event HashEvent(bytes32 newHash,uint8 eventType);

    constructor(address verusUpgradeAddress, address verusSerializerAddress, 
    address verusNotarizerAddress) 
    {
        verusUpgradeContract = verusUpgradeAddress;
        verusSerializer = VerusSerializer(verusSerializerAddress);
        verusNotarizer = VerusNotarizer(verusNotarizerAddress);
    }

    function setContract(address _contract) public {

        require(msg.sender == verusUpgradeContract);

        if ( _contract != address(verusSerializer))
            verusSerializer = VerusSerializer(_contract);
        
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
    
    function checkTransfers(VerusObjects.CReserveTransferImport calldata _import, bytes32 hashedTransfers) public view returns (uint256, uint128) {

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

            readerLen = verusSerializer.readCompactSizeLE(firstObj, OUTPUT_SCRIPT_OFFSET);    // get the length of the output script
            readerLen = verusSerializer.readCompactSizeLE(firstObj, readerLen.offset);        // then length of first master push

            // must be push less than 75 bytes, as that is an op code encoded similarly to a vector.
            // all we do here is ensure that is the case and skip master
            if (readerLen.value == 0 || readerLen.value > 0x4b)
            {
                return (uint256(0), uint128(0));
            }

            nextOffset = readerLen.offset + readerLen.value;        // add the length of the push of master to point to cc opcode

            assembly {
                var1 := mload(add(firstObj, nextOffset))         // this should be OP_CHECKCRYPTOCONDITION
                nextOffset := add(nextOffset, 1)                    // and after that...
                opCode2 := mload(add(firstObj, nextOffset))         // should be OP_PUSHDATA1 or OP_PUSHDATA2
                nextOffset := add(nextOffset, 1)                    // point to the length of the pushed data after CC instruction
            }

            if (var1 != SCRIPT_OP_CHECKCRYPTOCONDITION ||
                (opCode2 != SCRIPT_OP_PUSHDATA1 && opCode2 != SCRIPT_OP_PUSHDATA2))
            {
                return (uint256(0), uint128(0));
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
                return (uint256(0), uint128(0));
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
        return (uint256(0), uint128(0));
    }

    function checkCCEValues(bytes memory firstObj, uint32 nextOffset, bytes32 hashedTransfers, uint32 nIndex) public pure returns(uint256, uint128)
    {
        bytes32 incomingValue;
        address systemSourceID;
        address destSystemID;
        address destCurrencyID;
        address exporter;
        uint64 rewardFees;
        uint32 startheight;
        uint32 endheight;
        uint256 rewardAddressPlusFees;
        
        assembly {
            systemSourceID := mload(add(firstObj, nextOffset))      // source system ID, which should match expected source (VRSC/VRSCTEST)
            nextOffset := add(nextOffset, CCE_HASH_TRANSFERS_DELTA)
            incomingValue := mload(add(firstObj, nextOffset))       // get hash of reserve transfers from partial transaction proof
            nextOffset := add(nextOffset, CCE_DEST_SYSTEM_DELTA)
            destSystemID := mload(add(firstObj, nextOffset))        // destination system, which should be vETH
            nextOffset := add(nextOffset, CCE_DEST_CURRENCY_DELTA)
            destCurrencyID := mload(add(firstObj, nextOffset))      // destination currency, which should be vETH
            nextOffset := add(nextOffset, 2)                        // skip type and length 0x09 & 0x16
            nextOffset := add(nextOffset, CCE_DEST_CURRENCY_DELTA)
            exporter := mload(add(firstObj, nextOffset))            // exporter
            nextOffset := add(nextOffset, 9)                        // skip firstinput + numinputs + itterate next byte for varint
        }

        (startheight, nextOffset)  = readVarint(firstObj, nextOffset); 
        (endheight, nextOffset)  = readVarint(firstObj, nextOffset); 

        assembly {
            nextOffset := add(nextOffset, 1)                        // itterate next byte for mapsise
            nextOffset := add(nextOffset, CCE_DEST_CURRENCY_DELTA)
            rewardFees := mload(add(firstObj, nextOffset))    
        }
            // packed uint64 and uint160 into a uint256 for efficiency (fees and address)
            rewardAddressPlusFees = uint256(uint160(exporter));
            rewardAddressPlusFees |= uint256(rewardFees) << 160;

        if (!(hashedTransfers == incomingValue &&
                systemSourceID == VerusConstants.VerusSystemId &&
                destSystemID == VerusConstants.EthSystemID &&
                destCurrencyID == VerusConstants.VEth)) {

            revert("CCE information does not checkout");
        }

        return (rewardAddressPlusFees, uint128(startheight) | (uint128(endheight) << 32) | (uint128(nIndex) << 64) );

    }

    // roll through each proveComponents
    function proveComponents(VerusObjects.CReserveTransferImport memory _import) public view returns(bytes32 txRoot){
     
        bytes32 hashInProgress;
        bytes32 testHash;

        if (_import.partialtransactionproof.components.length > 0)
        {   
            hashInProgress = _import.partialtransactionproof.components[0].elVchObj.createHash();
            if (_import.partialtransactionproof.components[0].elType == 1 )
            {
                txRoot = checkProof(hashInProgress,_import.partialtransactionproof.components[0].elProof);           
            }
        }

        for (uint i = 1; i < _import.partialtransactionproof.components.length; i++) {
            hashInProgress = _import.partialtransactionproof.components[i].elVchObj.createHash();
            testHash = checkProof(hashInProgress,_import.partialtransactionproof.components[i].elProof);
        
            if (txRoot != testHash) 
            {
                txRoot = bytes32(0);
                break;
            }
        }

        return txRoot;
    }
    
    function proveImports(VerusObjects.CReserveTransferImport calldata _import, bytes32 hashOfTransfers) public view returns(uint256, uint128){
        
        bytes32 confirmedStateRoot;
        bytes32 retStateRoot;
        uint256 rewardAddPlusFees;
        uint128 heightsAndTXNum;

        (rewardAddPlusFees, heightsAndTXNum) = checkTransfers(_import, hashOfTransfers);
        
        bytes32 txRoot = proveComponents(_import);

        if(txRoot == bytes32(0))
        { 
            revert("Components do not validate"); 
        }

        retStateRoot = checkProof(txRoot, _import.partialtransactionproof.txproof);
        confirmedStateRoot = verusNotarizer.getBestStateroot();

        if (retStateRoot == bytes32(0) || retStateRoot != flipBytes32(confirmedStateRoot)) {

            revert("Stateroot does not match");
        }
        //truncate to only return heights as, contract will revert if issue with proofs.
        return (rewardAddPlusFees, heightsAndTXNum);
 
    }

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
  
    
}


