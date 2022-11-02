// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 < 0.9.0;
pragma abicoder v2;   
import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../Libraries/VerusConstants.sol";
import "../MMR/VerusBlake2b.sol";

contract VerusSerializer {

    uint constant ETH_ADDRESS_SIZE_BYTES = 20;
    uint32 constant CCC_PREFIX_TO_NAME_LEN = 4 + 4 + 20;
    uint32 constant CCC_ID_LEN = 20;
    uint32 constant CCC_NATIVE_OFFSET = 4 + 4 + 1;
    uint32 constant CCC_TOKENID_OFFSET = 32;
    int16 constant TYPE_ETHEREUM = 2;
    using VerusBlake2b for bytes;

    function readVarUintLE(bytes memory incoming, uint32 offset) public pure returns(VerusObjectsCommon.UintReader memory) {
        uint32 retVal = 0;
        while (true)
        {
            uint8 oneByte;
            assembly {
                oneByte := mload(add(incoming, offset))
            }
            retVal += (uint32)(oneByte & 0x7f) << (offset * 7);
            offset++;
            if (oneByte <= 0x7f)
            {
                break;
            }
        }
        return VerusObjectsCommon.UintReader(offset, retVal);
    }

    // uses the encoding from Bitcoin script pushes
    // this does not support numbers larger than uint16, and if it encounters one or any invalid data, it returns a value of 
    // zero and the original offset
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

    function writeVarInt(uint64 incoming) public pure returns(bytes memory) {
        bytes1 inProgress;
        bytes memory output;
        uint len = 0;
        while(true){
            inProgress = bytes1(uint8(incoming & 0x7f) | (len!=0 ? 0x80:0x00));
            output = abi.encodePacked(inProgress,output);
            if(incoming <= 0x7f) break;
            incoming = (incoming >> 7) -1;
            len++;
        }
        return output;
    }

   
    function writeCompactSize(uint newNumber) public pure returns(bytes memory) {
        bytes memory output;
        if (newNumber < uint8(253))
        {   
            output = abi.encodePacked(uint8(newNumber));
        }
        else if (newNumber <= 0xFFFF)
        {   
            output = abi.encodePacked(uint8(253),uint8(newNumber & 0xff),uint8(newNumber >> 8));
        }
        else if (newNumber <= 0xFFFFFFFF)
        {   
            output = abi.encodePacked(uint8(254),uint8(newNumber & 0xff),uint8(newNumber >> 8),uint8(newNumber >> 16),uint8(newNumber >> 24));
        }
        else 
        {   
            output = abi.encodePacked(uint8(254),uint8(newNumber & 0xff),uint8(newNumber >> 8),uint8(newNumber >> 16),uint8(newNumber >> 24),uint8(newNumber >> 32),uint8(newNumber >> 40),uint8(newNumber >> 48),uint8(newNumber >> 56));
        }
        return output;
    }

  
    //serialize functions
    
    function serializeString(string memory anyString) public pure returns(bytes memory){
        //naturally BigEndian
        bytes memory be;
        be = abi.encodePacked(anyString);
        return abi.encodePacked(writeCompactSize(be.length),anyString);
        //return abi.encodePacked(anyString);
    }


    function serializeBytes32(bytes32 anyBytes32) public pure returns(bytes32){
        //naturally BigEndian
        uint256 v;
        v = uint256(anyBytes32);
    
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
            
        return bytes32(v);
    }

    
    function serializeUint16(uint16 number) public pure returns(uint16){
        number = (number << 8) | (number >> 8) ;
        return number;
    }
    
    function serializeUint32(uint32 number) public pure returns(uint32){
        // swap bytes
        number = ((number & 0xFF00FF00) >> 8) | ((number & 0x00FF00FF) << 8);
        number = (number >> 16) | (number << 16);
        return number;
    }

    function serializeInt16(int16 number) public pure returns(int16){
        number = (number << 8) | (number >> 8) ;
        return number;
    }
    
    function serializeInt32(int32 inval) public pure returns(uint32){
        uint32 number = uint32(inval);
        number = ((number & 0xFF00FF00) >> 8) | ((number & 0x00FF00FF) << 8);
        number = (number >> 16) | (number << 16);
        return number;
    }
    
    function serializeInt64(int64 number) public pure returns(uint64){
        
        uint64 v = uint64(number);
        v = ((v & 0xFF00FF00FF00FF00) >> 8) |
        ((v & 0x00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = (v >> 32) | (v << 32);
        return v;
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

    function serializeInt32Array(int32[] memory numbers) public pure returns(bytes memory){
        bytes memory be;
        be = writeCompactSize((numbers.length));
        for(uint i = 0;i < numbers.length; i++){
            be = abi.encodePacked(be, serializeInt32(numbers[i]));
        }
        return be;
    }

    function serializeInt64Array(int64[] memory numbers) public pure returns(bytes memory){
        bytes memory be;
        be = writeCompactSize((numbers.length));
        for(uint i = 0;i < numbers.length; i++){
            be = abi.encodePacked(be, serializeInt64(numbers[i]));
        }
        return be;
    }

    function serializeUint160Array(uint160[] memory numbers) public pure returns(bytes memory){
        bytes memory be;
        be = writeCompactSize((numbers.length));
        for(uint i = 0;i < numbers.length; i++){
            be = abi.encodePacked(be,abi.encodePacked(numbers[i]));
        }
        return be;
    }

    function serializeCTransferDestination(VerusObjectsCommon.CTransferDestination memory ctd) public pure returns(bytes memory){

        uint256 destinationSize;

        if ((ctd.destinationtype & VerusConstants.DEST_REGISTERCURRENCY) == VerusConstants.DEST_REGISTERCURRENCY) {

            destinationSize = ctd.destinationaddress.length;

        } else {

            destinationSize = ETH_ADDRESS_SIZE_BYTES;
        }

        return abi.encodePacked(ctd.destinationtype, writeCompactSize(destinationSize),ctd.destinationaddress);
    }    

    function serializeCCurrencyValueMap(VerusObjects.CCurrencyValueMap memory _ccvm) public pure returns(bytes memory){
         return abi.encodePacked(_ccvm.currency, serializeUint64(_ccvm.amount));
    }
    
    function serializeCCurrencyValueMaps(VerusObjects.CCurrencyValueMap[] memory _ccvms) public pure returns(bytes memory){
        bytes memory inProgress;
        inProgress = writeVarInt(uint64(_ccvms.length));
        for(uint i=0; i < _ccvms.length; i++){
            inProgress = abi.encodePacked(inProgress,serializeCCurrencyValueMap(_ccvms[i]));
        }
        return inProgress;
    }

    function serializeCReserveTransfer(VerusObjects.CReserveTransfer memory ct) public pure returns(bytes memory){
        
        bytes memory output =  abi.encodePacked(
            writeVarInt(ct.version),
            ct.currencyvalue.currency, 
            writeVarInt(uint64(ct.currencyvalue.amount)), //special interpretation of a ccurrencyvalue
            writeVarInt(ct.flags),
            ct.feecurrencyid,
            writeVarInt(uint64(ct.fees)),
            serializeCTransferDestination(ct.destination),
            ct.destcurrencyid
           );
           
        if((ct.flags & VerusConstants.RESERVE_TO_RESERVE )>0) output = abi.encodePacked(output, ct.secondreserveid);           
         //see if it has a cross_system flag
        if((ct.flags & VerusConstants.CROSS_SYSTEM)>0) output = abi.encodePacked(output, ct.destsystemid);
        
        return output;
    }
    
    function serializeCReserveTransfers(VerusObjects.CReserveTransfer[] memory _bts, bool includeSize) public pure returns(bytes memory){
        bytes memory inProgress;
        
        if (includeSize) inProgress = writeCompactSize(_bts.length);
        
        for(uint i=0; i < _bts.length; i++){
            inProgress = abi.encodePacked(inProgress,serializeCReserveTransfer(_bts[i]));
        }
        return inProgress;
    }

    function serializeCUTXORef(VerusObjectsNotarization.CUTXORef memory _cutxo) public pure returns(bytes memory){
        return abi.encodePacked(
            serializeBytes32(_cutxo.hash),
            serializeUint32(_cutxo.n)
        );
    }

    function serializeCProofRoot(VerusObjectsNotarization.CProofRoot memory _cpr) public pure returns(bytes memory){
        
        bytes memory retval;

        retval = abi.encodePacked(
            _cpr.systemid,
            serializeInt16(_cpr.version),
            serializeInt16(_cpr.cprtype),
            _cpr.systemid,
            serializeUint32(_cpr.rootheight),
            serializeBytes32(_cpr.stateroot),
            serializeBytes32(_cpr.blockhash),
            serializeBytes32(_cpr.compactpower)
            );

        if (_cpr.cprtype == TYPE_ETHEREUM)    
            retval = abi.encodePacked(retval, serializeInt64(_cpr.gasprice));

        return retval;
    }

    function serializeProofRoots(VerusObjectsNotarization.ProofRoots memory _prs) public pure returns(bytes memory){
        return abi.encodePacked(
            _prs.currencyid,
            serializeCProofRoot(_prs.proofroot)
        );  
    }

    function serializeProofRootsArray(VerusObjectsNotarization.ProofRoots[] memory _prsa) public pure returns(bytes memory){
        bytes memory inProgress;
        
        inProgress = writeCompactSize(_prsa.length);
        for(uint i=0; i < _prsa.length; i++){
            inProgress = abi.encodePacked(inProgress,serializeProofRoots(_prsa[i]));
        }
        return inProgress;
    }
    
    function serializeCProofRootArray(VerusObjectsNotarization.CProofRoot[] memory _prsa) public pure returns(bytes memory){
        bytes memory inProgress;
        
        inProgress = writeCompactSize(_prsa.length);
        for(uint i=0; i < _prsa.length; i++){
            inProgress = abi.encodePacked(inProgress,serializeCProofRoot(_prsa[i]));
        }
        return inProgress;
    }
    

    function serializeCCoinbaseCurrencyState(VerusObjectsNotarization.CCoinbaseCurrencyState memory _cccs) public pure returns(bytes memory){
        bytes memory part1 = abi.encodePacked(
            serializeUint16(_cccs.version),
            serializeUint16(_cccs.flags),
            _cccs.currencyid,
            serializeUint160Array(_cccs.currencies),
            serializeInt32Array(_cccs.weights),
            serializeInt64Array(_cccs.reserves),
            writeVarInt(uint64(_cccs.initialsupply)),
            writeVarInt(uint64(_cccs.emitted)),
            writeVarInt(uint64(_cccs.supply))
        );
        bytes memory part2 = abi.encodePacked(
            serializeInt64(_cccs.primarycurrencyout),
            serializeInt64(_cccs.preconvertedout),
            serializeInt64(_cccs.primarycurrencyfees),
            serializeInt64(_cccs.primarycurrencyconversionfees),
            serializeInt64Array(_cccs.reservein),
            serializeInt64Array(_cccs.primarycurrencyin),
            serializeInt64Array(_cccs.reserveout),
            serializeInt64Array(_cccs.conversionprice),
            serializeInt64Array(_cccs.viaconversionprice),
            serializeInt64Array(_cccs.fees),
            serializeInt32Array(_cccs.priorweights),
            serializeInt64Array(_cccs.conversionfees)
        );
        
        return abi.encodePacked(part1,part2);
    }

    function serializeCurrencyStates(VerusObjectsNotarization.CurrencyStates memory _cs) public pure returns(bytes memory){
        return abi.encodePacked(
            _cs.currencyid,
            serializeCCoinbaseCurrencyState(_cs.currencystate)
        );
    }

    function serializeCurrencyStatesArray(VerusObjectsNotarization.CurrencyStates[] memory _csa) public pure returns(bytes memory){
        bytes memory inProgress;
        inProgress = writeCompactSize(_csa.length);
        for(uint i=0; i < _csa.length; i++){
            inProgress = abi.encodePacked(inProgress,serializeCurrencyStates(_csa[i]));
        }
        return inProgress;
    }

    function notarizationBlakeHash(bytes calldata _not) public view returns (bytes32)
    {
        return _not.createHash();

    }
    
    function serializeNodes(VerusObjectsNotarization.CNodeData[] memory _cnds) public pure returns(bytes memory){
        bytes memory inProgress;
        inProgress = writeCompactSize(_cnds.length);
        for(uint i=0; i < _cnds.length; i++){
            inProgress = abi.encodePacked(inProgress,serializeCNodeData(_cnds[i]));
        }
        return inProgress;
    }

    function serializeCNodeData(VerusObjectsNotarization.CNodeData memory _cnd) public pure returns(bytes memory){
        
        return abi.encodePacked(
            serializeString(_cnd.networkaddress),
            _cnd.nodeidentity
        );
    }

    function serializeCCrossChainExport(VerusObjects.CCrossChainExport memory _ccce) public pure returns(bytes memory){
        bytes memory part1 = abi.encodePacked(
            serializeUint16(_ccce.version),
            serializeUint16(_ccce.flags),
            _ccce.sourcesystemid,
            _ccce.hashtransfers,
            _ccce.destinationsystemid,
            _ccce.destinationcurrencyid);
        bytes memory part2 = abi.encodePacked(
            bytes2(0x0000), //Ctransferdesination is 00 type and 00 length for exporter
            serializeInt32(_ccce.firstinput),
            serializeUint32(_ccce.numinputs),
            writeVarInt(_ccce.sourceheightstart),
            writeVarInt(_ccce.sourceheightend),
            serializeCCurrencyValueMaps(_ccce.totalfees),
            serializeCCurrencyValueMaps(_ccce.totalamounts),
            serializeCCurrencyValueMaps(_ccce.totalburned),
            bytes1(0x00)); // Reservetransfers 
            
        return abi.encodePacked(part1,part2);

    }

    function flipArray(bytes memory incoming) public pure returns(bytes memory){
        uint256 len;
        len = incoming.length;
        bytes memory output = new bytes(len);
        uint256 pos = 0;
        while(pos < len){
            output[pos] = incoming[len - pos - 1];
            pos++;
        }
        return output;
    }

    function currencyParser(bytes memory input, uint256 offset) public pure
                    returns (VerusObjects.PackedCurrencyLaunch memory returnCurrency)
    {
        uint32 nextOffset;
        uint8 nameStringLength;
        address nativeCurrencyID;
        uint256 nftID;
        uint8 NativeCurrencyType;

        nextOffset = CCC_PREFIX_TO_NAME_LEN + uint32(offset);

        assembly {
            nameStringLength := mload(add(input, nextOffset)) // string length MAX 64 so will always be a byte
        }

        returnCurrency.nameAndFlags = nameStringLength > 19 ? 19 : nameStringLength; //first byte is length 

        for (uint32 i = 0; i < nameStringLength; i++) { //pack a max of 19 bytes of the id name into token name
            returnCurrency.nameAndFlags |= uint256(uint8(input[i + nextOffset])) << ((i+1)*8);
        }
        
        nextOffset += nameStringLength + CCC_ID_LEN ; // skip launchsysemID

        assembly {
            nextOffset := add(nextOffset, CCC_ID_LEN)
            nextOffset := add(nextOffset, CCC_NATIVE_OFFSET)
            NativeCurrencyType := mload(add(input, nextOffset)) 
        }
   
    
        if (NativeCurrencyType == VerusConstants.DEST_ETHNFT)
        {
            assembly {
                nextOffset := add(add(nextOffset, CCC_ID_LEN), 1) //skip vector length 
                nativeCurrencyID := mload(add(input, nextOffset))
                nextOffset := add(nextOffset, CCC_TOKENID_OFFSET)
                nftID := mload(add(input, nextOffset))
            }
            returnCurrency.nameAndFlags |= uint256(VerusConstants.TOKEN_ETH_NFT_DEFINITION) << 160;
            returnCurrency.nameAndFlags |= uint256(VerusConstants.MAPPING_ETHEREUM_OWNED) << 160;
        }
        else if (NativeCurrencyType == VerusConstants.DEST_ETH)
        {
            assembly {
                nextOffset := add(add(nextOffset, CCC_ID_LEN), 1) //skip vector length 
                nativeCurrencyID := mload(add(input, nextOffset))
            }
            returnCurrency.nameAndFlags |= uint256(VerusConstants.TOKEN_LAUNCH) << 160;
            returnCurrency.nameAndFlags |= uint256(VerusConstants.MAPPING_ETHEREUM_OWNED) << 160;
        }
        else if (NativeCurrencyType == 0x00)
        {
            returnCurrency.nameAndFlags |= uint256(VerusConstants.TOKEN_LAUNCH) << 160;
            returnCurrency.nameAndFlags |= uint256(VerusConstants.MAPPING_VERUS_OWNED) << 160;
        }

        returnCurrency.tokenID = nftID;
        returnCurrency.ERCContract = nativeCurrencyID;

        return returnCurrency;

    }

    function deserializeTransfers(bytes memory tempSerialized, uint8 numberOfTransfers) public pure
        returns (VerusObjects.PackedSend[] memory, VerusObjects.PackedCurrencyLaunch[] memory, uint32 counter)
    { 
        // return value counter is a packed 32bit number first bytes is number of transfers, 3rd byte number of ETH sends 4th byte number of currencey launches
              
        VerusObjects.PackedSend[] memory tempTransfers = new VerusObjects.PackedSend[](numberOfTransfers); 
        VerusObjects.PackedCurrencyLaunch[] memory launchTxs = new VerusObjects.PackedCurrencyLaunch[](2); //max to Currency launches
        address tempaddress;
        uint64 temporaryRegister1;
        uint8 destinationType;
        uint256 nextOffset = 21;
        uint64 flags;

        while (nextOffset <= tempSerialized.length) {
            
            assembly {
                tempaddress := mload(add(tempSerialized, nextOffset)) // skip version 0x01 (1 byte)
            }

            (temporaryRegister1, nextOffset)  = readVarint(tempSerialized, nextOffset);  //readvarint returns next idx position
            (flags, nextOffset) = readVarint(tempSerialized, nextOffset);

            tempTransfers[uint8(counter)].currencyAndAmount = uint256(temporaryRegister1) << 160; //shift amount and pack
            tempTransfers[uint8(counter)].currencyAndAmount |= uint256(uint160(tempaddress));

            nextOffset += 20; //skip feecurrency id always vETH, variint already 1 byte in so 19

            (temporaryRegister1, nextOffset) = readVarint(tempSerialized, nextOffset); //fees read into 'temporaryRegister1' but not used

            assembly {
                nextOffset := add(nextOffset, 1) //move to read the destination type
                destinationType := mload(add(tempSerialized, nextOffset))
                nextOffset := add(nextOffset, 1) //move to read destination vector length compactint
            }

            (temporaryRegister1, nextOffset) = readCompactSizeLE2(tempSerialized, nextOffset);    // get the length of the destination

            // if destination an address read 
            if (destinationType & VerusConstants.DEST_ETH == VerusConstants.DEST_ETH)
            {
                if (tempaddress == VerusConstants.VEth)
                {
                    tempTransfers[uint8(counter)].destinationAndFlags = uint256(VerusConstants.TOKEN_ETH_SEND) << 160;
                    counter |= (uint32((counter >> 16 & 0xff) + 1) << 16); //This is the ETH currency counter packed into the 3rd byte
                }
                else
                {
                    tempTransfers[uint8(counter)].destinationAndFlags = uint256(VerusConstants.TOKEN_ERC20_SEND) << 160;
                }

                assembly {
                    tempaddress := mload(sub(add(add(tempSerialized, nextOffset), temporaryRegister1), 1))
                }
                tempTransfers[uint8(counter)].destinationAndFlags |= uint256(uint160(tempaddress));
                counter++;
            }
            else if (destinationType == VerusConstants.DEST_REGISTERCURRENCY || destinationType == VerusConstants.DEST_ETHNFT)
            { 
                launchTxs[(counter >> 24 & 0xff)] = currencyParser(tempSerialized, nextOffset);
                launchTxs[(counter >> 24 & 0xff)].iaddress = address(uint160(tempTransfers[uint8(counter)].currencyAndAmount));
                counter |= (uint32((counter >> 24 & 0xff) + 1) << 24); //This is the Launch currency counter packed into the 4th byte
               
            }

            nextOffset += temporaryRegister1;

            if (destinationType & VerusConstants.FLAG_DEST_AUX == VerusConstants.FLAG_DEST_AUX)
            {
                 (temporaryRegister1, nextOffset) = readCompactSizeLE2(tempSerialized, nextOffset);    // get the length of the auxDest
                 uint arraySize = temporaryRegister1;
                 for (uint i = 0; i < arraySize; i++)
                 {
                     (temporaryRegister1, nextOffset) = readCompactSizeLE2(tempSerialized, nextOffset);    // get the length of the auxDest sub array
                     nextOffset += temporaryRegister1;
                 }
            }

            if(destinationType & VerusConstants.FLAG_DEST_GATEWAY == VerusConstants.FLAG_DEST_GATEWAY )
            {
                 nextOffset += 56; //skip gatewayid, gatewaycode + fees
            }

            nextOffset += 20; //skip destCurrencyID

            if(destinationType & VerusConstants.RESERVE_TO_RESERVE == VerusConstants.RESERVE_TO_RESERVE)
            {
                 nextOffset += 20; 
            }

            if(flags & VerusConstants.CROSS_SYSTEM == VerusConstants.CROSS_SYSTEM )
            {
                 nextOffset += 20; 
            }

            
            nextOffset += 20; //offset ready for next address deserilization

        }

        return (tempTransfers, launchTxs, counter);

    }
        
    function readVarint(bytes memory buf, uint idx) public pure returns (uint64 v, uint retidx) {

        uint8 b; // store current byte content

        for (uint i = 0; i < 10; i++) {
            b = uint8(buf[i+idx]);
            v = (v << 7) | b & 0x7F;
            if (b & 0x80 == 0x80)
                v++;
            else
            return (v, idx + i + 1);
        }
        revert(); // i=9, invalid varint stream
    }

   function readCompactSizeLE2(bytes memory incoming, uint256 offset) public pure returns(uint64 v, uint retidx) {

        uint8 oneByte;
        assembly {
            oneByte := mload(add(incoming, offset))
        }
        offset++;
        if (oneByte < 253)
        {
            return (uint64(oneByte), offset);
        }
        else if (oneByte == 253)
        {
            offset++;
            uint16 twoByte;
            assembly {
                twoByte := mload(add(incoming, offset))
            }
            return (((twoByte << 8) & 0xffff)  | twoByte >> 8, offset + 1);
        }
        return (0, offset);
    }

}