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
    address immutable MKR;
    address immutable tBTC = 0xf87F6d4412dAd7c4452e8293850Df5327f02C308; // tBTC iaddress iS8TfRPfVpKo5FVfSUzfHBQxo9KuzpnqLU as hex
    address immutable vUSDC = 0x1Bd15cDbf0B5B8c9CC361FFBaf6D76cc2CdfD667; // vUSDC iaddress i61cV2uicKSi1rSMQCBNQeSYC3UAi9GVzd as hex

    constructor(address vETH, address Bridge, address Verus, address Dai, address Mkr){

        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
        DAI = Dai;
        MKR = Mkr;
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
    uint8 constant PROOF_TYPE_ETH = 2;
    uint32 constant FLAG_START_NOTARIZATION = 4;
    uint32 constant FLAG_LAUNCH_CONFIRMED = 8;
    uint32 constant FLAG_LAUNCH_COMPLETE = 0x100;
    uint32 constant FLAG_CONTRACT_UPGRADE = 0x200;
    uint32 constant REQUIRED_NOTARIZATION_FLAGS = FLAG_START_NOTARIZATION + FLAG_LAUNCH_CONFIRMED + FLAG_LAUNCH_COMPLETE;
    uint32 constant ALLOWED_OPTIONAL_NOTARIZATION_FLAGS = FLAG_CONTRACT_UPGRADE;
    uint32 constant ALLOWED_NOTARIZATION_FLAGS = REQUIRED_NOTARIZATION_FLAGS + ALLOWED_OPTIONAL_NOTARIZATION_FLAGS;
    enum Currency {VETH, DAI, VERUS, MKR}

    function initialize() external {
        // NOTE: removed as already ran.
        // rollingVoteIndex = VerusConstants.DEFAULT_INDEX_VALUE;
        // NOTE: New contract corrections July 2026
        verusToERC20mapping[VETH].tokenIndex = (address(this).balance / VerusConstants.SATS_TO_WEI_STD) + 118651397044 + 556405765;  // 8 decimal places VRSC SATS ETH 1186.51397044 in Verus, 5.56405765 in unclaimed fees.
        verusToERC20mapping[tBTC].tokenIndex += 7603215250; // 8 decimal places VRSC SATS tBTC 76.03215250
        verusToERC20mapping[vUSDC].tokenIndex += 14765883679800; // 8 decimal places VRSC SATS USDC 147,658.83679800
        // NOTE: Reset lastImportInfo to last known good export:
        //   Verus sourceheightend 4070448
        //   txid (verus) 7712d764c1cfa4758faa3fa2c9bf96e1928d23c5658c4932e0a8d18879220a69, txoutnum 0
        //   hashtransfers (verus) 42412cbbb5222979a701e711ce864b0cda823e77b036a59a10d968c1eb9979f3
        lastImportInfo[VerusConstants.SUBMIT_IMPORTS_LAST_TXID] = VerusObjects.lastImportInfo(
            bytes32(0xf37999ebc168d9109aa536b0773e82da0c4b86ce11e701a7792922b5bb2c4142), // hashtransfers reversed
            bytes32(0x690a227988d1a8e032498c65c5238d92e196bfc9a23faa8f75a4cfc164d71277), // exporttxid reversed
            0,       // exporttxoutnum
            4070448  // sourceheightend
        );

        // Block attacker/stuck CCEs from re-submission (each key is the display txid byte-reversed).
        // 9b045a80c036fd737dec10fd4f6415887a05529ecb20c8189a2098d97dff6038 (height 4070982)
        processedTxids[bytes32(0x3860ff7dd998209a18c820cb9e52057a8815644ffd10ec7d73fd36c0805a049b)] = true;
        // 97e1c41f0b2889a46ddfe519df5a0fbf24ec562fba73627f093290dd15e400f8 (height 4070995)
        processedTxids[bytes32(0xf800e415dd9032097f6273ba2f56ec24bf0f5adf19e5df6da489280b1fc4e197)] = true;
        // 7af0be458eaf3773f551c71b2cf6584add01b278fb55dfa5a50d549b802e7f1e (height 4071014)
        processedTxids[bytes32(0x1e7f2e809b540da5a5df55fb78b201dd4a58f62c1bc751f57337af8e45bef07a)] = true;
        // f899e6984dc7c3d7737bbca5d87db3682de355743349d40396a5fc34b9f5a733 (height 4071017)
        processedTxids[bytes32(0x33a7f5b934fca59603d449337455e32d68b37dd8a5bc7b73d7c3c74d98e699f8)] = true;    }
    
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

        require(
            (notarizationFlags & REQUIRED_NOTARIZATION_FLAGS) == REQUIRED_NOTARIZATION_FLAGS &&
            (notarizationFlags & ~ALLOWED_NOTARIZATION_FLAGS) == 0,
            "invalid notarization flags"
        );

        assembly {
                    nextOffset := add(nextOffset, 1)  // move to read type
                    proposerType := mload(add(nextOffset, notarization))
                    if gt(and(proposerType, 0xff), 0) {
                        nextOffset := add(nextOffset, 21) // move to proposer, type and vector length
                        proposerMain := mload(add(nextOffset, notarization))
                        //remove type flags of proposer.
                        proposerMain := and(proposerMain, 0x0fffffffffffffffffffffffffffffffffffffffffff)
                    }
                 }

        if (proposerType & VerusConstants.FLAG_DEST_GATEWAY == VerusConstants.FLAG_DEST_GATEWAY)
        {
            nextOffset += VerusConstants.FLAG_DEST_GATEWAY_LENGTH;  // skip past gateway ID to get to auxdest vector length
        }

        if (proposerType & VerusConstants.FLAG_DEST_AUX == VerusConstants.FLAG_DEST_AUX)
        {
            nextOffset += 1;  // goto auxdest parent vec length position
            nextOffset = processAux(notarization, nextOffset);
            nextOffset -= 1;  // NOTE: Next Varint call takes array pos not array pos +1
        }
        //position 0 of the rolling vote is use to determine whether votes have started
        else if (rollingVoteIndex != VerusConstants.DEFAULT_INDEX_VALUE){
            castVote(address(0));
        }

        address currencyid;
        assembly {
                    nextOffset := add(nextOffset, CURRENCY_LENGTH) //skip currencyid
                    currencyid := mload(add(notarization, nextOffset))      // currencyid
                 }
        require(currencyid == VETH, "invalid notarization currencyid");

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

        (stateRoot, height) = deserializeProofRoots(notarization, uint32(readerLen.value), nextOffset);
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
        uint daiEthVRSCMKRReserves;
        if (currencyid == BRIDGE && bridgeConverterActive) {
            daiEthVRSCMKRReserves = getReserves(notarization, nextOffset, uint8(readerLen.value));
            claimableFees[bytes32(uint256(uint160(VerusConstants.VDXF_ETH_DAI_VRSC_LAST_RESERVES)))] = daiEthVRSCMKRReserves; //store the fees in the notaryFeePool
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

    function getReserves (bytes memory notarization, uint32 nextOffset, uint8 currenciesLen) private view returns (uint) {
        
        
        Currency[4] memory currencyIndexes;

        for (uint8 i = 0; i < currenciesLen; i++)
        {
            address currency;
            assembly {
                    nextOffset := add(nextOffset, CURRENCY_LENGTH) // move to  read currency length
                    currency := mload(add(notarization, nextOffset)) // move to  read currencyid
                }
            if (currency == VETH)
            {
               currencyIndexes[i] = Currency.VETH;
            }
            else if (currency == DAI)
            {
               currencyIndexes[i] = Currency.DAI;
            }
            else if (currency == VERUS)
            {
               currencyIndexes[i] = Currency.VERUS;
            }
            else if (currency == MKR)
            {
               currencyIndexes[i] = Currency.MKR;
            }
            
        }

        //Skip the weights
        nextOffset = nextOffset + 1 + (uint32(currenciesLen) * 4) + 1; //move to read len of reserves

        //read the reserves, position [0..63] for DAI, [64..127] for ETH  [128..191] for VRSC pack into uint 64bit chunks
        uint256 ethToDaiRatios;
        for (uint8 i = 0; i < currenciesLen; i++)
        {
            uint64 reserve;
            assembly {
                    nextOffset := add(nextOffset, UINT64_BYTES_SIZE) // move to  read currency length
                    reserve := mload(add(notarization, nextOffset)) // move to  read currencyid
                }

            ethToDaiRatios |= uint256(serializeUint64(reserve)) << (uint256(currencyIndexes[i]) << 6);
        }

        assembly {                    
            nextOffset := add(nextOffset, 1) // move forward to read next varint.
        }

        return ethToDaiRatios;  
    }

    function deserializeProofRoots (bytes memory notarization, uint32 size, uint32 nextOffset) private view returns (bytes32 stateRoot, uint32 height)
    {
        for (uint i = 0; i < size; i++)
        {
            uint16 proofType;
            address systemID;
            bytes32 tempStateRoot;
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
                nextOffset := add(nextOffset, BYTES32_LENGTH) // move to power
            }
            
            if(systemID == VERUS)
            {
                stateRoot = tempStateRoot;
                height = serializeUint32(tempHeight); //swapendian
            }

            //swap 16bit endian
            if(((proofType >> 8) | (proofType << 8)) == PROOF_TYPE_ETH){
                assembly {
                    nextOffset := add(nextOffset, 8) // move to gasprice
                }
            }
        }
 
    }
    function readVarintStruct(bytes memory buf, uint idx) public pure returns (VerusObjectsCommon.UintReader memory) {
        uint8 b;
        uint64 v;
        uint retidx;
    
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
        return VerusObjectsCommon.UintReader(uint32(retidx), v);
    }
    
    function processAux (bytes memory firstObj, uint32 nextOffset) private returns (uint32)
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

                    castVote(tempAddress);
                    
                    nextOffset = (readerLen.offset + uint32(readerLen.value));
            }
            return nextOffset;
    }

    function castVote(address votetxid) private {

        // If the vote is address(0) and the vote has not started, or the vote hash has already been used, return
        if ((votetxid == address(0) && rollingVoteIndex == VerusConstants.DEFAULT_INDEX_VALUE)
                || successfulVoteHashes[votetxid] == VerusConstants.MAX_UINT256) {
            return;
        }

        // if the vote hash has not been used, save the vote start timestamp
        if(votetxid != address(0) && successfulVoteHashes[votetxid] == 0) {
            successfulVoteHashes[votetxid] = block.timestamp;
        } else if (votetxid != address(0) && (block.timestamp - successfulVoteHashes[votetxid]) > (VerusConstants.SECONDS_IN_DAY * 20)) {
            // if 20 days have passed since the vote started, set the vote hash as used
            successfulVoteHashes[votetxid] = VerusConstants.MAX_UINT256;

            // reset the rolling vote index to DEFAULT, if there are other hashes they will continue, otherwise voting will go idle.
            rollingVoteIndex = VerusConstants.DEFAULT_INDEX_VALUE;
            return;
        }
        
        if(rollingVoteIndex > (VerusConstants.VOTE_LENGTH - 1)) {
            rollingVoteIndex = 0;
        } else {
            rollingVoteIndex = rollingVoteIndex + 1;
        }

        // save an empty global write if the value to be written is the same as the current value
        if (votetxid != rollingUpgradeVotes[rollingVoteIndex]) {
            rollingUpgradeVotes[rollingVoteIndex] = votetxid;
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
            offset += 2; // skip marker(1) + align so 2-byte value is in mload LSBs
            uint16 twoByte;
            assembly {
                twoByte := mload(add(incoming, offset))
            }
 
            return VerusObjectsCommon.UintReader(offset + 1, ((twoByte << 8) & 0xffff)  | twoByte >> 8);
        }
        else if (oneByte == 254)
        {
            offset += 4; // skip marker(1) + align so 4-byte value is in mload LSBs
            uint32 fourByte;
            assembly {
                fourByte := mload(add(incoming, offset))
            }
            return VerusObjectsCommon.UintReader(offset + 1, serializeUint32(fourByte));
        }
        else
        {
            offset += 8; // skip marker(1) + align so 8-byte value is in mload LSBs
            uint64 eightByte;
            assembly {
                eightByte := mload(add(incoming, offset))
            }
            return VerusObjectsCommon.UintReader(offset + 1, serializeUint64(eightByte));
        }
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


