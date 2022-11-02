// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0;
pragma abicoder v2;
import "../Libraries/VerusObjects.sol";
import "./VerusBlake2b.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusMMR.sol";

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
    uint8 constant FLAG_FRACTIONAL = 1;
    uint8 constant FLAG_REFUNDING = 4;
    uint8 constant FLAG_LAUNCHCONFIRMED = 0x10;
    uint8 constant FLAG_LAUNCHCOMPLETEMARKER = 0x20;

    address verusUpgradeContract;

    constructor(address verusUpgradeAddress, address verusSerializerAddress, 
    address verusNotarizerAddress) 
    {
        verusUpgradeContract = verusUpgradeAddress;
        verusSerializer = VerusSerializer(verusSerializerAddress);
        verusNotarizer = VerusNotarizer(verusNotarizerAddress);
    }

    function setContracts(address[13] memory contracts) public {

        require(msg.sender == verusUpgradeContract);

        verusSerializer = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]);
        verusNotarizer = VerusNotarizer(contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
        
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

    function checkCCEValues(bytes memory firstObj, uint32 nextOffset, bytes32 hashedTransfers, uint32 nIndex) public view returns(uint256, uint128)
    {
        bytes32 hashReserveTransfers;
        address systemSourceID;
        address destSystemID;
        uint176 exporter;
        uint64 rewardFees;
        uint32 tempRegister;
        uint8 feeVectorSize;
        uint128 packedRegister; //uint128(startheight) | (uint128(endheight) << 32) | (uint128(nIndex) << 64) | (uint128(numInputs) << 96));
        uint256 rewardAddressPlusFees;
        
        assembly {
            systemSourceID := mload(add(firstObj, nextOffset))      // source system ID, which should match expected source (VRSC/VRSCTEST)
            nextOffset := add(nextOffset, CCE_HASH_TRANSFERS_DELTA)
            hashReserveTransfers := mload(add(firstObj, nextOffset))       // get hash of reserve transfers from partial transaction proof
            nextOffset := add(nextOffset, CCE_DEST_SYSTEM_DELTA)
            destSystemID := mload(add(firstObj, nextOffset))        // destination system, which should be vETH
            nextOffset := add(nextOffset, CCE_DEST_CURRENCY_DELTA)
            nextOffset := add(nextOffset, 2)                        // skip type and length 0x09 & 0x16
            nextOffset := add(nextOffset, CCE_DEST_CURRENCY_DELTA)
            exporter := mload(add(firstObj, nextOffset))            // exporter
            nextOffset := add(nextOffset, 8)                        // skip firstinput and go to no. transfers
            tempRegister := mload(add(firstObj, nextOffset))           //number of transfers                  
        }

        (packedRegister, nextOffset)  = readVarint(firstObj, nextOffset);  // put startheight at [0] 32bit chunk
        tempRegister = verusSerializer.serializeUint32(tempRegister); // reverse endian of no. transfers
        packedRegister  |= (uint128(tempRegister) << 96) ;  // put number of transfers at [3] 32-bit chunk     
        
        (tempRegister, nextOffset)  = readVarint(firstObj, nextOffset); 
        packedRegister  |= (uint128(tempRegister) << 32) ;  // put endheight at [1] 32 bit chunk
        packedRegister  |= (uint128(nIndex) << 64) ;  // put nindex at [2] 32 bit chunk
        assembly {
            nextOffset := add(nextOffset, 1)                        // itterate next byte for mapsize
            feeVectorSize := mload(add(firstObj, nextOffset)) 
        }

        if (feeVectorSize == 1) 
        {
            assembly {
                nextOffset := add(add(nextOffset, CCE_DEST_CURRENCY_DELTA), 8)  // move 20 + 8 bytes for (address + 64bit)
                rewardFees := mload(add(firstObj, nextOffset))    
            }
                // packed uint64 and uint160 into a uint256 for efficiency (fees and address)
                rewardAddressPlusFees = uint256(exporter);
                rewardFees = verusSerializer.serializeUint64(rewardFees);
                rewardAddressPlusFees |= uint256(rewardFees) << 176;
        }

        if (!(hashedTransfers == hashReserveTransfers &&
                systemSourceID == VerusConstants.VerusSystemId &&
                destSystemID == VerusConstants.EthSystemID)) {

            revert("CCE information does not checkout");
        }

        return (rewardAddressPlusFees, packedRegister); //uint128(startheight) | (uint128(endheight) << 32) | (uint128(nIndex) << 64) | (uint128(numInputs) << 96));

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
        confirmedStateRoot = verusNotarizer.getLastConfirmedVRSCStateRoot();

        if (retStateRoot == bytes32(0) || retStateRoot != confirmedStateRoot) {

            revert("Stateroot does not match");
        }
        //truncate to only return heights as, contract will revert if issue with proofs.
        return (rewardAddPlusFees, heightsAndTXNum);
 
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


