// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.22;
pragma abicoder v2;
import "../Libraries/VerusObjects.sol";
import "./VerusBlake2b.sol";
import {VerusSerializer} from "../VerusBridge/VerusSerializer.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusMMR.sol";
import "../Storage/StorageMaster.sol";

contract VerusProof is VerusStorage  {
    
    address immutable VETH;
    address immutable BRIDGE;
    address immutable VERUS;
    uint constant FORKS_DATA_OFFSET_FOR_HEIGHT = 224;
    uint constant FORKS_PROPOSER_SLOT = 2;

    constructor(address vETH, address Bridge, address Verus){

        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
    }

    using VerusBlake2b for bytes;
    
    // these constants should be able to reference each other, as many are relative, but Solidity does not
    // allow referencing them and still considering the result a constant. For any changes to these constants,
    // which are designed to ensure smart transaction provability, care must be take to ensure that OUTPUT_SCRIPT_OFFSET
    // is present and substituted for all equivalent values (currently (32 + 8))
    uint8 constant CCE_EVAL_EXPORT = 0xc;
    uint8 constant BRANCH_MMRBLAKE_NODE = 2;      // CMerkleBranchBase::BRANCH_MMRBLAKE_NODE
    uint8 constant VERSION_TXHASH_CAP = 2;         // only proofs with version >= this are accepted
    uint8 constant TX_PREVOUTSEQ = 2;              // CTransactionHeader::TX_PREVOUTSEQ
    uint8 constant TX_SIGNATURE_TYPE = 3;          // CTransactionHeader::TX_SIGNATURE
    uint8 constant CCOPTPARAMS_VERSION = 3;
    uint8 constant TX_SHIELDEDSPEND = 5;           // CTransactionHeader::TX_SHIELDEDSPEND
    uint8 constant TX_SHIELDEDOUTPUT = 6;          // CTransactionHeader::TX_SHIELDEDOUTPUT
    uint32 constant CCE_HASH_TRANSFERS_DELTA = 32;
    uint32 constant CCE_DEST_SYSTEM_DELTA = 20;
    uint32 constant CCE_DEST_CURRENCY_DELTA = 20;
    uint32 constant CCE_SOURCE_SYSTEM_DELTA = 20;  // advance past flags(2) to sourceSystemID... no: flags read inline, then +20 for sourceID

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
    uint8 constant TX_HEADER = 1;
    uint8 constant NUM_TX_PROOFS = 3;

    bytes16 constant _SYMBOLS = "0123456789abcdef";

    function checkProof(bytes32 hashToProve, VerusObjects.CTXProof[] memory _branches) public view returns(bytes32){
        //loop through the branches from bottom to top
        bytes32 hashInProgress = hashToProve;

        require(_branches.length > 0);
        
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
    
    // Fields extracted from a CCrossChainExport serialization.
    // Only the subset needed for import validation is populated.
    struct CCEData {
        address sourceSystemID;       // CCE.sourceSystemID  (uint160)
        bytes32 hashReserveTransfers; // CCE.hashReserveTransfers (uint256)
        address destSystemID;         // CCE.destSystemID    (uint160)
        address destCurrencyID;       // CCE.destCurrencyID  (uint160)
        uint176 exporter;             // CCE.exporter destination (type+address, ≤22 bytes)
        uint32  numInputs;            // CCE.numInputs       (num reserve transfers)
        uint32  sourceHeightStart;    // CCE.sourceHeightStart (VARINT)
        uint32  sourceHeightEnd;      // CCE.sourceHeightEnd   (VARINT)
    }

    // Parse a serialized CTxOut (firstObj) to locate the CCrossChainExport body.
    //
    // CTxOut wire format (from CTxOut::SerializationOp):
    //   nValue(8 LE) | compact-size(scriptLen) | script
    // NOTE: CTxOut::interest is a runtime field only — it is NOT written by SerializationOp.
    //
    // CScript layout (CScript::IsPayToCryptoCondition / CScript::GetOp2):
    //   Step 2  direct push (0x01-0x4b)  → master COptCCParams
    //   Step 3  OP_CHECKCRYPTOCONDITION (0xcc)
    //   Step 4  PUSHDATA1/2              → secondary COptCCParams body
    //   Step 5  direct push ≥4 bytes     → {version, evalCode, m, n}
    //   Step 6  n × direct push          → keys (all ≤75 bytes each)
    //   Step 7  PUSHDATA1/2              → CCE serialization blob
    //
    // Canonical push encoding is enforced (mirrors Bitcoin minimal-push rules):
    //   0x01-0x4b — canonical for dataLen 1-75
    //   0x4c (PUSHDATA1) — canonical for 76 ≤ dataLen ≤ 255
    //   0x4d (PUSHDATA2) — canonical for 256 ≤ dataLen ≤ 65535
    //
    // Returns (offset one-past CCE.flags, true) or (0, false) on any failure.
    function _parseCTxOut(bytes memory firstObj)
        private pure
        returns (uint32 nextOffset, bool ok)
    {
        if (firstObj.length < OUTPUT_SCRIPT_OFFSET) return (0, false);

        // Step 1: skip nValue(8) and read scriptPubKey compact-size inline (LE encoding).
        //   single-byte form used for values 0-252,
        //   0xfd two-byte form used for 253-65535.
        //   0xfe/0xff forms imply script > 65535 bytes — rejected for our use case.
        {
            uint8 leadByte;
            uint32 scriptLen;
            assembly { leadByte := mload(add(firstObj, OUTPUT_SCRIPT_OFFSET)) }
            if (leadByte < 253) {
                scriptLen  = uint32(leadByte);
                nextOffset = OUTPUT_SCRIPT_OFFSET + 1;
            } else if (leadByte == 253) {
                if (firstObj.length < OUTPUT_SCRIPT_OFFSET + 2) return (0, false);
                uint8 lo; uint8 hi;
                assembly {
                    lo := mload(add(firstObj, add(OUTPUT_SCRIPT_OFFSET, 1)))
                    hi := mload(add(firstObj, add(OUTPUT_SCRIPT_OFFSET, 2)))
                }
                scriptLen = uint32(lo) | (uint32(hi) << 8);
                require(scriptLen >= 253, "Non-canonical compact-size");
                nextOffset = OUTPUT_SCRIPT_OFFSET + 3;
            } else {
                return (0, false); // 4- or 8-byte compact-size: script too large
            }
            // Mirrors IsPayToCryptoCondition: 0 < scriptLen ≤ MAX_SCRIPT_SIZE (10000).
            if (scriptLen == 0 || scriptLen > 10000) return (0, false);
            // Full script must fit within firstObj.
            if (firstObj.length < nextOffset + scriptLen - 1) return (0, false);
        }
        uint8 op;

        // Step 2: master COptCCParams — must be a direct push (opcode 0x01-0x4b).
        assembly { op := mload(add(firstObj, nextOffset)) }
        nextOffset++;
        if (op < 0x01 || op > 0x4b) return (0, false);
        nextOffset += uint32(op); // skip firstParam data vector

        // Step 3: OP_CHECKCRYPTOCONDITION (0xcc).
        assembly { op := mload(add(firstObj, nextOffset)) }
        nextOffset++;
        if (op != SCRIPT_OP_CHECKCRYPTOCONDITION) return (0, false);

        // Step 4: PUSHDATA1/2 wrapping the secondary COptCCParams body.
        // Canonical check: PUSHDATA1 only if dataLen > 75; PUSHDATA2 only if dataLen > 255.
        {
            uint8 lenLo;
            assembly { op := mload(add(firstObj, nextOffset)) }
            nextOffset++;
            if (op == SCRIPT_OP_PUSHDATA1) {
                assembly { lenLo := mload(add(firstObj, nextOffset)) }
                if (lenLo <= 75) return (0, false); // non-canonical
                nextOffset += 1;
            } else if (op == SCRIPT_OP_PUSHDATA2) {
                uint8 lenHi;
                assembly {
                    lenLo := mload(add(firstObj, nextOffset))
                    lenHi := mload(add(firstObj, add(nextOffset, 1)))
                }
                if (uint32(lenLo) | (uint32(lenHi) << 8) <= 255) return (0, false); // non-canonical
                nextOffset += 2;
            } else {
                return (0, false);
            }
        }
        // nextOffset now points to the first byte of the secondary COptCCParams body.

        // Step 5: {version, evalCode, m, n} — a direct push of ≥4 bytes.
        {
            uint8 version; 
            uint8 evalCode;
            uint8 nKeys;
            assembly { op := mload(add(firstObj, nextOffset)) }
            nextOffset++;
            if (op < 0x04 || op > 0x4b) return (0, false);
            // nextOffset-1 = version, nextOffset = evalCode, nextOffset+1 = m, nextOffset+2 = n
            assembly {
                version  := mload(add(firstObj, nextOffset))
                evalCode := mload(add(firstObj, add(nextOffset, 1)))
                // skip m keys
                nKeys    := mload(add(firstObj, add(nextOffset, 3)))
            }
            if (evalCode != CCE_EVAL_EXPORT || version != CCOPTPARAMS_VERSION) return (0, false);
            if (nKeys > 10) return (0, false); // sanity cap
            nextOffset += uint32(op); // skip all header data bytes

            // Step 6: skip n key pushes (each a direct push, opcode 0x01-0x4b).
            // Key types (PKH/ID/SH/PK) are always ≤75 bytes, so PUSHDATA1/2 is unexpected.
            for (uint8 i = 0; i < nKeys; i++) {
                assembly { op := mload(add(firstObj, nextOffset)) }
                nextOffset++;
                if (op < 0x01 || op > 0x4b) return (0, false);
                nextOffset += uint32(op);
            }
        }

        // Step 7: CCE data push (PUSHDATA1 or PUSHDATA2), canonical length enforced.
        // dOff = assembly-offset of first CCE byte (CCE.nVersion[0]).
        uint32 dOff;
        {
            uint8 lenLo;
            assembly { op := mload(add(firstObj, nextOffset)) }
            nextOffset++;
            if (op == SCRIPT_OP_PUSHDATA1) {
                assembly { lenLo := mload(add(firstObj, nextOffset)) }
                if (lenLo <= 75) return (0, false); // non-canonical
                nextOffset += 1;
            } else if (op == SCRIPT_OP_PUSHDATA2) {
                uint8 lenHi;
                assembly {
                    lenLo := mload(add(firstObj, nextOffset))
                    lenHi := mload(add(firstObj, add(nextOffset, 1)))
                }
                if (uint32(lenLo) | (uint32(lenHi) << 8) <= 255) return (0, false); // non-canonical
                nextOffset += 2;
            } else {
                return (0, false);
            }
            dOff = nextOffset;
        }

        // _readCCEFields expects nextOffset = dOff + 3, so that:
        //   data[nextOffset-4..nextOffset-3] = CCE.nVersion LE
        //   data[nextOffset-2..nextOffset-1] = CCE.flags    LE
        nextOffset = dOff + 3;
        return (nextOffset, true);
    }

    // Deserialize the CCrossChainExport fields that are needed for import validation.
    // nextOffset must be the value returned by _parseCTxOut (assembly convention,
    // pointing one-past CCE.flags so that data[nextOffset-2..nextOffset-1] = CCE.flags LE).
    //
    // Field layout starting from CCE.nVersion (4 bytes before nextOffset):
    //   nVersion(2) | flags(2) | sourceSystemID(20) | hashReserveTransfers(32) |
    //   destSystemID(20) | destCurrencyID(20) | exporter(CTransferDestination) |
    //   firstInput(4 LE) | numInputs(4 LE) | VARINT(sourceHeightStart) | VARINT(sourceHeightEnd)
    function _readCCEFields(bytes memory firstObj, uint32 nextOffset)
        private pure
        returns (CCEData memory cce)
    {
        // Validate CCE nVersion == 1 (LE bytes 0x01 0x00; read big-endian = 0x0100).
        // CCE.nVersion is 4 bytes before nextOffset: data[nextOffset-4..nextOffset-3].
        // uint16 mload at (nextOffset-2) reads the last 2 bytes = data[nextOffset-4..nextOffset-3].
        uint16 cceNVersion;
        assembly { cceNVersion := mload(add(firstObj, sub(nextOffset, 2))) }
        require(cceNVersion == 0x0100, "CCE nVersion must be 1");

        // Only FLAG_POSTLAUNCH (0x0080) may be set; no other CCE flags are accepted.
        // Exactly 0x8000 means flags_lo == 0x80 (FLAG_POSTLAUNCH) and flags_hi == 0x00.
        assembly {
            if iszero(eq(and(mload(add(firstObj, nextOffset)), 0xFFFF), 0x8000)) { revert(0, 0) }
        }

        // sourceSystemID (uint160, 20 bytes): advance past it and read as address
        nextOffset += CCE_SOURCE_SYSTEM_DELTA;
        address srcSys;
        assembly { srcSys := mload(add(firstObj, nextOffset)) }
        cce.sourceSystemID = srcSys;

        // hashReserveTransfers (uint256, 32 bytes)
        nextOffset += CCE_HASH_TRANSFERS_DELTA;
        bytes32 hRT;
        assembly { hRT := mload(add(firstObj, nextOffset)) }
        cce.hashReserveTransfers = hRT;

        // destSystemID (uint160, 20 bytes)
        nextOffset += CCE_DEST_SYSTEM_DELTA;
        address dstSys;
        assembly { dstSys := mload(add(firstObj, nextOffset)) }
        cce.destSystemID = dstSys;

        // destCurrencyID (uint160, 20 bytes)
        nextOffset += CCE_DEST_CURRENCY_DELTA;
        address dstCur;
        assembly { dstCur := mload(add(firstObj, nextOffset)) }
        cce.destCurrencyID = dstCur;

        // exporter (CTransferDestination): type(1 byte) | length(1 byte) | dest-bytes
        nextOffset += 1;
        uint8 exporterType;
        assembly { exporterType := mload(add(firstObj, nextOffset)) }

        nextOffset += 1;
        uint8 exporterLen;
        assembly { exporterLen := mload(add(firstObj, nextOffset)) }
        if (exporterLen > 0) {
            nextOffset += exporterLen;
            uint176 exporterVal;
            assembly { exporterVal := mload(add(firstObj, nextOffset)) }
            cce.exporter = exporterVal;
        }

        // Optional gateway ID prefix (FLAG_DEST_GATEWAY = 128): skip 48 bytes
        if (exporterType & VerusConstants.FLAG_DEST_GATEWAY == VerusConstants.FLAG_DEST_GATEWAY) {
            nextOffset += VerusConstants.FLAG_DEST_GATEWAY_LENGTH;
        }

        // Optional AUX destination (FLAG_DEST_AUX = 64): may override exporter with ETH address
        if (exporterType & VerusConstants.FLAG_DEST_AUX == VerusConstants.FLAG_DEST_AUX) {
            nextOffset += 1;
            uint176 auxAddr;
            (nextOffset, auxAddr) = readAuxDest(firstObj, nextOffset, 0);
            nextOffset -= 1;  // readAuxDest returns assembly offset; readVarint below needs it unchanged
            if (auxAddr != 0) cce.exporter = auxAddr;
        }

        // firstInput (int32 LE, 4 bytes) is skipped; numInputs (int32 LE, 4 bytes) is read.
        // After += 8, the rightmost 4 bytes of mload = numInputs bytes in memory order.
        // serializeUint32 byte-reverses to obtain the correct integer value.
        uint32 numInputsRaw;
        assembly {
            nextOffset  := add(nextOffset, 8)
            numInputsRaw := mload(add(firstObj, nextOffset))
        }
        cce.numInputs = serializeUint32(numInputsRaw);

        // VARINT(sourceHeightStart) then VARINT(sourceHeightEnd)
        uint32 startH;
        uint32 endH;
        (startH, nextOffset) = readVarint(firstObj, nextOffset);
        cce.sourceHeightStart = startH;
        (endH, nextOffset)    = readVarint(firstObj, nextOffset);
        cce.sourceHeightEnd   = endH;

        require(firstObj[firstObj.length - 1] == 0x75, "Script must end with OP_DROP (0x75)");
    }

    function checkExportAndTransfers(VerusObjects.CReserveTransferImport memory _import, bytes32 hashedTransfers) public view returns (uint128, uint176) {


        for (uint i = 1; i < _import.partialtransactionproof.components.length; i++) {
            if (_import.partialtransactionproof.components[i].elType != TYPE_TX_OUTPUT)
                continue;

            bytes memory firstObj = _import.partialtransactionproof.components[i].elVchObj;
            uint32 nIndex = _import.partialtransactionproof.components[i].elProof[0].proofSequence.nIndex;

            // Parse CTxOut: validate scriptPubKey structure and locate the CCE body
            (uint32 cceBodyOffset, bool ok) = _parseCTxOut(firstObj);
            if (!ok) return (uint128(0), uint176(0));

            // Deserialize CCE fields from the located body
            CCEData memory cce = _readCCEFields(firstObj, cceBodyOffset);

            // Validate: correct source chain, correct destination chain, correct currency, correct transfer hash
            if (!(cce.hashReserveTransfers == hashedTransfers &&
                  cce.sourceSystemID == VERUS &&
                  cce.destSystemID   == VETH &&
                  cce.destCurrencyID == VETH)) {
                revert("CCE information does not checkout");
            }

            // Pack heights + nIndex + numInputs into a single uint128 for the caller.
            // Layout (matches SubmitImports unpack convention):
            //   bits  0-31 : sourceHeightStart
            //   bits 32-63 : sourceHeightEnd
            //   bits 64-95 : nIndex (output position in the tx)
            //   bits 96-127: numInputs (= number of reserve transfers)
            uint128 packed = uint128(cce.sourceHeightStart)
                           | (uint128(cce.sourceHeightEnd) << 32)
                           | (uint128(nIndex)              << 64)
                           | (uint128(cce.numInputs)       << 96);

            return (packed, cce.exporter);
        }
        return (uint128(0), uint176(0));
    }

    function readAuxDest (bytes memory firstObj, uint32 nextOffset, uint176 exporter) private pure returns (uint32, uint176)
    {
                                                  
            VerusObjectsCommon.UintReader memory readerLen;
            readerLen = readCompactSizeLE(firstObj, nextOffset);    // get the length of the auxDest
            nextOffset = readerLen.offset;
            uint arraySize = readerLen.value;
            
            for (uint i = 0; i < arraySize; i++)
            {
                    readerLen = readCompactSizeLE(firstObj, nextOffset);    // get the length of the auxDest sub array
                    if (readerLen.value == AUX_DEST_ETH_VEC_LENGTH)
                    {
                         assembly {
                            exporter := mload(add(add(firstObj, nextOffset),AUX_DEST_ETH_VEC_LENGTH))
                         }
                    }

                    nextOffset = (readerLen.offset + uint32(readerLen.value));
            }
            return (nextOffset, exporter);
    }

    // Returns the MMR leaf position for a given transaction element type and sub-index.
    // Mirrors the layout used by _CTransactionMap in transaction.cpp:
    //   pos 0            : TX_HEADER
    //   pos 1..nVins     : TX_PREVOUTSEQ[0..nVins-1]
    //   pos nVins+1..2*nVins : TX_SIGNATURE[0..nVins-1]
    //   pos 2*nVins+1..  : TX_OUTPUT[0..nVouts-1]
    //   pos ..           : TX_SHIELDEDSPEND, TX_SHIELDEDOUTPUT
    function _mmrPosition(
        uint8 elType, uint8 elIdx,
        uint32 nVins, uint32 nVouts, uint32 nShieldedSpends
    ) private pure returns (uint32) {
        if (elType == TX_PREVOUTSEQ)    return 1 + uint32(elIdx);
        if (elType == TX_SIGNATURE_TYPE) return 1 + nVins + uint32(elIdx);
        if (elType == TYPE_TX_OUTPUT)   return 1 + 2 * nVins + uint32(elIdx);
        if (elType == TX_SHIELDEDSPEND)  return 1 + 2 * nVins + nVouts + uint32(elIdx);
        if (elType == TX_SHIELDEDOUTPUT) return 1 + 2 * nVins + nVouts + nShieldedSpends + uint32(elIdx);
        revert("Unknown elType");
    }

    // Validates the MMR proof structure of the partial transaction proof against the
    // parsed transaction header counts
    //   - component[0] has exactly one BRANCH_MMRBLAKE_NODE proof covering elHashSize elements
    //     at position 0 (the header)
    //   - anti-spoofing size check (capped: last branch hash == elHashSize;
    //     uncapped: no hash in the proof sequence is <= UINT16_MAX)
    //   - each subsequent component has a valid proof pointing to the expected MMR position
    //     for its (elType, elIdx) pair, and its element index is within the known bounds
    function _validateHeaderProof(
        VerusObjects.CReserveTransferImport memory _import,
        uint32 elHashSize,
        uint32 nVins,
        uint32 nVouts,
        uint32 nShieldedSpends
    ) private pure {
        VerusObjects.CComponents memory comp0 = _import.partialtransactionproof.components[0];

        // component[0] must declare itself as a TX_HEADER; this is also enforced downstream
        // by proveComponents and checkExportAndTransfers, but fail fast here.
        require(comp0.elType == TX_HEADER, "comp0 must be TX_HEADER");

        require(
            comp0.elProof.length == 1 &&
            comp0.elProof[0].branchType == BRANCH_MMRBLAKE_NODE,
            "Invalid header proof type"
        );

        VerusObjects.CMerkleBranch memory b0 = comp0.elProof[0].proofSequence;

        require(elHashSize > 0,                "Empty tx element set");
        require(b0.nSize == elHashSize,        "Header nSize mismatch");
        // GetMMRProofIndex(0, nSize, 0) always returns 0; header must be at position 0
        require(b0.nIndex == 0,                "Header nIndex must be 0");
        require(b0.branch.length > 0,          "Empty header branch");

        // --- Anti-spoofing check (capped proofs only) ---
        // The last branch element encodes the total element count, preventing the prover
        // from extending the tree to a larger size than was actually committed.
        require(
            _import.partialtransactionproof.version >= VERSION_TXHASH_CAP,
            "Only capped proofs accepted"
        );
        require(
            uint256(b0.branch[b0.branch.length - 1]) == elHashSize,
            "Capped: size hash mismatch"
        );

        // --- Per-component structural validation ---
        // Each component i >= 1 must:
        //   1. Have exactly one BRANCH_MMRBLAKE_NODE proof over the same elHashSize tree.
        //   2. Claim an element index within the known bounds for its type.
        //   3. Declare an nIndex equal to the expected MMR leaf position for (elType, elIdx).
        //      (The cryptographic proof that this hash is in the tree is done by proveComponents.)
        for (uint i = 1; i < _import.partialtransactionproof.components.length; i++) {
            VerusObjects.CComponents memory comp = _import.partialtransactionproof.components[i];

            require(
                comp.elProof.length == 1 &&
                comp.elProof[0].branchType == BRANCH_MMRBLAKE_NODE &&
                comp.elProof[0].proofSequence.nSize == elHashSize,
                "Component proof invalid"
            );

            uint8 elType = comp.elType;
            uint8 elIdx  = comp.elIdx;

            // Bounds check per element type
            if (elType == TX_PREVOUTSEQ || elType == TX_SIGNATURE_TYPE) {
                require(elIdx < nVins,          "vin idx out of bounds");
            } else if (elType == TYPE_TX_OUTPUT) {
                require(elIdx < nVouts,         "vout idx out of bounds");
            } else if (elType == TX_SHIELDEDSPEND) {
                require(elIdx < nShieldedSpends, "shielded spend idx OOB");
            }

            // nIndex must match the expected MMR leaf position for this element
            uint32 expected = _mmrPosition(elType, elIdx, nVins, nVouts, nShieldedSpends);
            require(
                comp.elProof[0].proofSequence.nIndex == expected,
                "Component nIndex mismatch"
            );
        }
    }

    // roll through each proveComponents
    function proveComponents(VerusObjects.CReserveTransferImport memory _import) public view returns(bytes32 txRoot){
     
        bytes32 hashInProgress;
        bytes32 testHash;
  
        hashInProgress = _import.partialtransactionproof.components[0].elVchObj.createHash();
        if (_import.partialtransactionproof.components[0].elType == TX_HEADER )
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
    
    function proveImports(bytes calldata dataIn ) external view returns(uint128, uint176){
        
        // txCounts packs: bits 0-31 elHashSize, 32-63 nVins, 64-95 nVouts, 96-127 nShieldedSpends
        (VerusObjects.CReserveTransferImport memory _import, bytes32 hashOfTransfers, uint128 txCounts) =
            abi.decode(dataIn, (VerusObjects.CReserveTransferImport, bytes32, uint128));

        uint32 elHashSize     = uint32(txCounts);
        uint32 nVins          = uint32(txCounts >> 32);
        uint32 nVouts         = uint32(txCounts >> 64);
        uint32 nShieldedSpends = uint32(txCounts >> 96);

        // Validate MMR proof structure and anti-spoofing before processing export data
        _validateHeaderProof(_import, elHashSize, nVins, nVouts, nShieldedSpends);

        bytes32 confirmedStateRoot;
        bytes32 retStateRoot;
        uint176 exporter;
        uint128 heightsAndTXNum;

        (heightsAndTXNum, exporter) = checkExportAndTransfers(_import, hashOfTransfers);
        
        bytes32 txRoot = proveComponents(_import);

        if(txRoot == bytes32(0))
        { 
            revert("Components do not validate"); 
        }
        
        require(_import.partialtransactionproof.txproof.length == NUM_TX_PROOFS);

        retStateRoot = checkProof(txRoot, _import.partialtransactionproof.txproof);
        confirmedStateRoot = getLastConfirmedVRSCStateRoot();

        if (retStateRoot == bytes32(0) || retStateRoot != confirmedStateRoot) {

            revert("Stateroot does not match");
        }
        //truncate to only return heights as, contract will revert if issue with proofs.
        return (heightsAndTXNum, exporter);
 
    }

    function getLastConfirmedVRSCStateRoot() public view returns (bytes32) {

        bytes storage tempArray = bestForks[0];
        if (tempArray.length == 0)
        {
            return bytes32(0);
        }

        bytes32 stateRoot;
        uint32 height;
        bytes32 slot;

        assembly {
                    mstore(add(slot, 32),tempArray.slot)
                    height := shr(FORKS_DATA_OFFSET_FOR_HEIGHT, sload(add(keccak256(add(slot, 32), 32), FORKS_PROPOSER_SLOT)))
        }
        tempArray = proofs[bytes32(uint256(height))];

        assembly {
                mstore(add(slot, 32),tempArray.slot)
                stateRoot := sload(add(keccak256(add(slot, 32), 32), 0))
        }

        return stateRoot;
    }

    function readVarint(bytes memory buf, uint idx) public pure returns (uint32 v, uint32 retidx) {
        uint8 b;
    
        assembly {  ///assemmbly  2267 GAS
            let end := add(idx, 10)
            let i := idx
            retidx := add(idx, 1)
            for {} lt(i, end) {} {
                b := mload(add(buf, retidx))
                i := add(i, 1)
                v := or(shl(7, v), and(b, 0x7f))
                if iszero(eq(and(b, 0x80), 0x80)) {
                    break
                }
                v := add(v, 1)
                retidx := add(retidx, 1)
            }
        }
    }

    function getTokenList(uint256 start, uint256 end) public view returns(VerusObjects.setupToken[] memory ) {

        uint tokenListLength;
        tokenListLength = tokenList.length;
        VerusObjects.mappedToken memory recordedToken;
        uint i;
        uint endPoint;

        endPoint = tokenListLength - 1;
        if (start >= 0 && start < tokenListLength)
        {
            i = start;
        }

        if (end > i && end < tokenListLength)
        {
            endPoint = end;
        }
        VerusObjects.setupToken[] memory temp = new VerusObjects.setupToken[]((endPoint - i) + 1);

        uint j;
        for(; i <= endPoint; i++) {

            address iAddress;
            iAddress = tokenList[i];
            recordedToken = verusToERC20mapping[iAddress];
            temp[j].iaddress = iAddress;
            temp[j].flags = recordedToken.flags;

            if (iAddress == VETH)
            {
                temp[j].erc20ContractAddress = address(0);
                temp[j].name = recordedToken.name;
                temp[j].ticker = "ETH";
            }
            else if(recordedToken.flags & VerusConstants.MAPPING_ERC20_DEFINITION == VerusConstants.MAPPING_ERC20_DEFINITION )
            {
                temp[j].erc20ContractAddress = recordedToken.erc20ContractAddress;
                temp[j].name = recordedToken.name;
            }
            else if(recordedToken.flags & VerusConstants.MAPPING_ERC721_NFT_DEFINITION == VerusConstants.MAPPING_ERC721_NFT_DEFINITION
                        || recordedToken.flags & VerusConstants.MAPPING_ERC1155_NFT_DEFINITION == VerusConstants.MAPPING_ERC1155_NFT_DEFINITION
                        || recordedToken.flags & VerusConstants.MAPPING_ERC1155_ERC_DEFINITION == VerusConstants.MAPPING_ERC1155_ERC_DEFINITION)
            {
                temp[j].erc20ContractAddress = recordedToken.erc20ContractAddress;
                temp[j].name = recordedToken.name;
                temp[j].tokenID = recordedToken.tokenID;
            }
            j++;
        }

        return temp;
    }

    function serializeUint32(uint32 number) private pure returns(uint32){
        // swap bytes
        number = ((number & 0xFF00FF00) >> 8) | ((number & 0x00FF00FF) << 8);
        number = (number >> 16) | (number << 16);
        return number;
    }    

    function readCompactSizeLE(bytes memory incoming, uint32 offset) private pure returns(VerusObjectsCommon.UintReader memory) {

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
            uint16 value16 = ((twoByte << 8) & 0xffff) | twoByte >> 8;
            require(value16 >= 253, "Non-canonical compact-size");
            return VerusObjectsCommon.UintReader(offset + 1, value16);
        }
        else if (oneByte == 254)
        {
            offset += 3;
            uint32 fourByte;
            assembly {
                fourByte := mload(add(incoming, offset))
            }
            uint32 value32 = serializeUint32(fourByte);
            require(value32 >= 65536, "Non-canonical compact-size");
            return VerusObjectsCommon.UintReader(offset + 3, value32);
        }
        else
        {
            revert("Compact-size too large");
        }
    }
}


