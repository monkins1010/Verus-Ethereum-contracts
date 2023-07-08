// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.22 < 0.9.0;
pragma abicoder v2;   
import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../Libraries/VerusConstants.sol";

contract VerusSerializer {

    uint constant ETH_ADDRESS_SIZE_BYTES = 20;
    uint32 constant CCC_PREFIX_TO_OPTIONS = 3 + 4; // already starts on the byte so 3 first
    uint32 constant CCC_ID_LEN = 20;
    uint32 constant CCC_NATIVE_OFFSET = 4 + 4 + 1;
    uint32 constant CCC_TOKENID_OFFSET = 32;

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
        uint32 nameStringLength;
        address parent;
        address nativeCurrencyID;
        uint256 nftID;
        uint8 NativeCurrencyType;
        uint32 options;

        nextOffset = CCC_PREFIX_TO_OPTIONS + uint32(offset);

        assembly {
            options := mload(add(input, nextOffset))
            nextOffset := add(nextOffset, CCC_ID_LEN)
            parent := mload(add(input, nextOffset))
            nextOffset := add(nextOffset, 1)  // one byte for name string length
            nameStringLength := and(mload(add(input, nextOffset)), 0x000000ff) // string length MAX 64 so will always be a byte
        }

        options = serializeUint32(options);  //reverse endian
        returnCurrency.parent = parent;
        bytes memory tempname = new bytes(nameStringLength);

        for (uint32 i = 0; i < nameStringLength; i++) { //pack a max of 19 bytes of the id name into token name
            tempname[i] = input[i + nextOffset];
        }
        
        returnCurrency.name = string(tempname);
        nextOffset += nameStringLength;
        assembly {
            nextOffset := add(nextOffset, CCC_ID_LEN) // move to read launchsystemID
            nextOffset := add(nextOffset, CCC_ID_LEN) // move to read Native currency
            nextOffset := add(nextOffset, CCC_NATIVE_OFFSET)
            NativeCurrencyType := mload(add(input, nextOffset)) 
        }
       
        if (NativeCurrencyType & VerusConstants.DEST_ETHNFT == VerusConstants.DEST_ETHNFT) //mapped ETH NFT
        {
            assembly {
                nextOffset := add(add(nextOffset, CCC_ID_LEN), 1) //skip vector length 
                nativeCurrencyID := mload(add(input, nextOffset))
                nextOffset := add(nextOffset, CCC_TOKENID_OFFSET)
                nftID := mload(add(input, nextOffset))
            }
            returnCurrency.flags |= uint8(VerusConstants.TOKEN_ETH_NFT_DEFINITION);
            returnCurrency.flags |= uint8(VerusConstants.MAPPING_ETHEREUM_OWNED);
            returnCurrency.tokenID = nftID;
        }
        else if (NativeCurrencyType & VerusConstants.DEST_ETH == VerusConstants.DEST_ETH) //mapped ETH token
        {
            assembly {
                nextOffset := add(add(nextOffset, CCC_ID_LEN), 1) //skip vector length 
                nativeCurrencyID := mload(add(input, nextOffset))
            }
            returnCurrency.flags |= uint8(VerusConstants.TOKEN_LAUNCH);
            returnCurrency.flags |= uint8(VerusConstants.MAPPING_ETHEREUM_OWNED);
        }
        else if (options & VerusConstants.OPTION_NFT_TOKEN == VerusConstants.OPTION_NFT_TOKEN) //minted NFT from verus
        {
            returnCurrency.flags |= uint8(VerusConstants.TOKEN_ETH_NFT_DEFINITION);
            returnCurrency.flags |= uint8(VerusConstants.MAPPING_VERUS_OWNED);
            nativeCurrencyID = VerusConstants.VerusNFTID;
        }
        else if (NativeCurrencyType == 0x00) //minted ERC20 from verus
        {
            returnCurrency.flags |= uint8(VerusConstants.TOKEN_LAUNCH);
            returnCurrency.flags |= uint8(VerusConstants.MAPPING_VERUS_OWNED);
        }

        returnCurrency.ERCContract = nativeCurrencyID;

        return returnCurrency;

    }

    function deserializeTransfers(bytes memory tempSerialized, uint8 numberOfTransfers) public pure
        returns (VerusObjects.PackedSend[] memory tempTransfers, VerusObjects.PackedCurrencyLaunch[] memory launchTxs, uint32 counter, uint176[] memory refundAddresses)
    { 
        // return value counter is a packed 32bit number first bytes is number of transfers, 3rd byte number of ETH sends 4th byte number of currencey launches
              
        tempTransfers = new VerusObjects.PackedSend[](numberOfTransfers); 
        refundAddresses = new uint176[](numberOfTransfers);
        launchTxs = new VerusObjects.PackedCurrencyLaunch[](2); //max to Currency launches
        address tempaddress;
        uint64 temporaryRegister1;
        uint8 destinationType;
        uint256 nextOffset = 21;
        uint176 refundAddress;
        uint64 flags;

        while (nextOffset <= tempSerialized.length) {
            
            assembly {
                tempaddress := mload(add(tempSerialized, nextOffset)) // skip version 0x01 (1 byte) and read currency being sent
            }

            (temporaryRegister1, nextOffset)  = readVarint(tempSerialized, nextOffset);  // read varint (amount) returns next idx position
            (flags, nextOffset) = readVarint(tempSerialized, nextOffset);

            tempTransfers[uint8(counter)].currencyAndAmount = uint256(temporaryRegister1) << VerusConstants.UINT160_BITS_SIZE; //shift amount and pack
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
                tempTransfers[uint8(counter)].destinationAndFlags = uint256(tempaddress == VerusConstants.VEth ? VerusConstants.TOKEN_ETH_SEND : VerusConstants.TOKEN_ERC20_SEND) << VerusConstants.UINT160_BITS_SIZE;

                assembly {
                    tempaddress := mload(sub(add(add(tempSerialized, nextOffset), temporaryRegister1), 1)) //skip type +1 byte to read address
                }
                tempTransfers[uint8(counter)].destinationAndFlags |= uint256(uint160(tempaddress));
            }
            else if (destinationType & VerusConstants.DEST_REGISTERCURRENCY == VerusConstants.DEST_REGISTERCURRENCY || 
                                destinationType & VerusConstants.DEST_ETHNFT == VerusConstants.DEST_ETHNFT)
            { 
                launchTxs[(counter >> 24 & 0xff)] = currencyParser(tempSerialized, nextOffset);
                launchTxs[(counter >> 24 & 0xff)].iaddress = address(uint160(tempTransfers[uint8(counter)].currencyAndAmount));
                counter += 0x1000000; //This is the Launch currency counter packed into the 4th byte
            }

            nextOffset += temporaryRegister1;

            if (destinationType & VerusConstants.FLAG_DEST_AUX == VerusConstants.FLAG_DEST_AUX)
            {
                (temporaryRegister1, nextOffset) = readCompactSizeLE2(tempSerialized, nextOffset);    // get the length of the auxDest

                for (uint i = temporaryRegister1; i > 0; i--) {
                    (temporaryRegister1, nextOffset) = readCompactSizeLE2(tempSerialized, nextOffset);    // get the length of the auxDest sub array
                    assembly {
                        refundAddress := mload(sub(add(add(tempSerialized, nextOffset), temporaryRegister1), 1)) //skip type +1 byte to read address
                    }
                    refundAddresses[uint8(counter)] = refundAddress;
                nextOffset += temporaryRegister1;
                }

            }
            counter++;
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

        return (tempTransfers, launchTxs, counter, refundAddresses);

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