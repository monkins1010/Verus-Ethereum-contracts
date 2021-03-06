// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 < 0.9.0;
pragma experimental ABIEncoderV2;   
import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../Libraries/VerusConstants.sol";

contract VerusSerializer {

    uint constant ETH_ADDRESS_SIZE_BYTES = 20;

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
            assembly {
                oneByte := mload(add(incoming, offset))
            }
            uint16 twoByte = oneByte;
            offset++;
            assembly {
                oneByte := mload(add(incoming, offset))
            }
            return VerusObjectsCommon.UintReader(offset + 1, (twoByte << 8) + oneByte);
        }
        return VerusObjectsCommon.UintReader(offset, 0);
    }

    function writeVarInt(uint256 incoming) public pure returns(bytes memory) {
        bytes1 inProgress;
        bytes memory output;
        uint len = 0;
        while(true){
            inProgress = bytes1(uint8(incoming & 0x7f) | (len!=0 ? 0x80:0x00));
            output = abi.encodePacked(output,inProgress);
            if(incoming <= 0x7f) break;
            incoming = (incoming >> 7) -1;
            len++;
        }
        return flipArray(output);
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

    
    function verusHashPrefix(string memory prefix,address systemID,int64 blockHeight,address signingID, bytes memory messageToHash) public pure returns(bytes memory){
        return abi.encodePacked(serializeString(prefix),serializeAddress(systemID),serializeInt64(blockHeight),serializeAddress(signingID),messageToHash);    
    }
    
    //serialize functions

    function serializeBool(bool anyBool) public pure returns(bytes memory){
        return abi.encodePacked(anyBool);
    }
    
    function serializeString(string memory anyString) public pure returns(bytes memory){
        //naturally BigEndian
        bytes memory be;
        be = abi.encodePacked(anyString);
        return abi.encodePacked(writeCompactSize(be.length),anyString);
        //return abi.encodePacked(anyString);
    }

    function serializeBytes20(bytes20 anyBytes20) public pure returns(bytes memory){
        //naturally BigEndian
        return abi.encodePacked(anyBytes20);
    }
    function serializeBytes32(bytes32 anyBytes32) public pure returns(bytes memory){
        //naturally BigEndian
        return flipArray(abi.encodePacked(anyBytes32));
    }

    function serializeUint8(uint8 number) public pure returns(bytes memory){
        bytes memory be = abi.encodePacked(number);
        return(flipArray(be));
    }
    
    function serializeUint16(uint16 number) public pure returns(bytes memory){
        bytes memory be = abi.encodePacked(number);
        return(flipArray(be));
    }
    
    function serializeUint32(uint32 number) public pure returns(bytes memory){
        bytes memory be = abi.encodePacked(number);
        return(flipArray(be));
    }

    function serializeInt16(int16 number) public pure returns(bytes memory){
        bytes memory be = abi.encodePacked(number);
        return(flipArray(be));
    }
    
    function serializeInt32(int32 number) public pure returns(bytes memory){
        bytes memory be = abi.encodePacked(number);
        return(flipArray(be));
    }
    
    function serializeInt64(int64 number) public pure returns(bytes memory){
        bytes memory be = abi.encodePacked(number);
        return(flipArray(be));
    }

    function serializeInt32Array(int32[] memory numbers) public pure returns(bytes memory){
        bytes memory be;
        be = writeCompactSize((numbers.length));
        for(uint i = 0;i < numbers.length; i++){
            be = abi.encodePacked(be,serializeInt32(numbers[i]));
        }
        return be;
    }

    function serializeInt64Array(int64[] memory numbers) public pure returns(bytes memory){
        bytes memory be;
        be = writeCompactSize((numbers.length));
        for(uint i = 0;i < numbers.length; i++){
            be = abi.encodePacked(be,flipArray(abi.encodePacked(numbers[i])));
        }
        return be;
    }

    function serializeUint64(uint64 number) public pure returns(bytes memory){
        bytes memory be = abi.encodePacked(number);
        return(flipArray(be));
    }

    function serializeAddress(address number) public pure returns(bytes memory){
        bytes memory be = abi.encodePacked(number);
        return be;
    }
    
    function serializeUint160Array(uint160[] memory numbers) public pure returns(bytes memory){
        bytes memory be;
        be = writeCompactSize((numbers.length));
        for(uint i = 0;i < numbers.length; i++){
            be = abi.encodePacked(be,abi.encodePacked(numbers[i]));
        }
        return(be);
    }

    function serializeUint256(uint256 number) public pure returns(bytes memory){
        bytes memory be = abi.encodePacked(number);
        return(flipArray(be));
    }
    
    function serializeCTransferDestination(VerusObjectsCommon.CTransferDestination memory ctd) public pure returns(bytes memory){

        uint256 destinationSize;

        if ((ctd.destinationtype & VerusConstants.DEST_REGISTERCURRENCY) == VerusConstants.DEST_REGISTERCURRENCY) {

            destinationSize = ctd.destinationaddress.length;

        } else {

            destinationSize = ETH_ADDRESS_SIZE_BYTES;
        }

        return abi.encodePacked(serializeUint8(ctd.destinationtype),writeCompactSize(destinationSize),ctd.destinationaddress);
    }    

    function serializeCCurrencyValueMap(VerusObjects.CCurrencyValueMap memory _ccvm) public pure returns(bytes memory){
         return abi.encodePacked(serializeAddress(_ccvm.currency),serializeUint64(_ccvm.amount));
    }
    
    function serializeCCurrencyValueMaps(VerusObjects.CCurrencyValueMap[] memory _ccvms) public pure returns(bytes memory){
        bytes memory inProgress;
        inProgress = writeVarInt(_ccvms.length);
        for(uint i=0; i < _ccvms.length; i++){
            inProgress = abi.encodePacked(inProgress,serializeCCurrencyValueMap(_ccvms[i]));
        }
        return inProgress;
    }

    function serializeCReserveTransfer(VerusObjects.CReserveTransfer memory ct) public pure returns(bytes memory){
        
        bytes memory output =  abi.encodePacked(
            writeVarInt(ct.version),
            abi.encodePacked(serializeAddress(ct.currencyvalue.currency),writeVarInt(ct.currencyvalue.amount)),//special interpretation of a ccurrencyvalue
            writeVarInt(ct.flags),
            serializeAddress(ct.feecurrencyid),
            writeVarInt(ct.fees),
            serializeCTransferDestination(ct.destination),
            serializeAddress(ct.destcurrencyid)
           );
           
        if((ct.flags & VerusConstants.RESERVE_TO_RESERVE )>0) output = abi.encodePacked(output,serializeAddress(ct.secondreserveid));           
         //see if it has a cross_system flag
        if((ct.flags & VerusConstants.CROSS_SYSTEM)>0) output = abi.encodePacked(output,serializeAddress(ct.destsystemid));
        
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
        return abi.encodePacked(
            serializeAddress(_cpr.systemid),
            serializeInt16(_cpr.version),
            serializeInt16(_cpr.cprtype),
            serializeAddress(_cpr.systemid),
            serializeUint32(_cpr.rootheight),
            serializeBytes32(_cpr.stateroot),
            serializeBytes32(_cpr.blockhash),
            serializeBytes32(_cpr.compactpower)
            );
    }

    function serializeProofRoots(VerusObjectsNotarization.ProofRoots memory _prs) public pure returns(bytes memory){
        return abi.encodePacked(
            serializeAddress(_prs.currencyid),
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
            serializeAddress(_cccs.currencyid),
            serializeUint160Array(_cccs.currencies),
            serializeInt32Array(_cccs.weights),
            serializeInt64Array(_cccs.reserves),
            writeVarInt(uint256(int256(_cccs.initialsupply))),
            writeVarInt(uint256(int256(_cccs.emitted))),
            writeVarInt(uint256(int256(_cccs.supply)))
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
            serializeAddress(_cs.currencyid),
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

    function serializeCPBaaSNotarization(VerusObjectsNotarization.CPBaaSNotarization memory _not) public pure returns(bytes memory){
        return abi.encodePacked(
            writeVarInt(_not.version),
            writeVarInt(_not.flags),
            serializeCTransferDestination(_not.proposer),
            serializeAddress(_not.currencyid),
            serializeCCoinbaseCurrencyState(_not.currencystate),
            serializeUint32(_not.notarizationheight),
            serializeCUTXORef(_not.prevnotarization),
            serializeBytes32(_not.hashprevnotarization),
            serializeUint32(_not.prevheight),
            serializeCurrencyStatesArray(_not.currencystates),
            serializeCProofRootArray(_not.proofroots),
            serializeNodes(_not.nodes)
        );
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
            serializeAddress(_cnd.nodeidentity)
        );
    }

    function serializeCCrossChainExport(VerusObjects.CCrossChainExport memory _ccce) public pure returns(bytes memory){
        bytes memory part1 = abi.encodePacked(
            serializeUint16(_ccce.version),
            serializeUint16(_ccce.flags),
            serializeAddress(_ccce.sourcesystemid),
            flipArray(serializeBytes32(_ccce.hashtransfers)),
            serializeAddress(_ccce.destinationsystemid),
            serializeAddress(_ccce.destinationcurrencyid));
        bytes memory part2 = abi.encodePacked(
            writeVarInt(_ccce.sourceheightstart),
            writeVarInt(_ccce.sourceheightend),
            serializeUint32(_ccce.numinputs),
            serializeCCurrencyValueMaps(_ccce.totalamounts),
            serializeCCurrencyValueMaps(_ccce.totalfees),
            serializeCCurrencyValueMaps(_ccce.totalburned),
            serializeCTransferDestination(_ccce.rewardaddress),
            serializeInt32(_ccce.firstinput),
            bytes1(0x00));
            
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

    function deSerializeCurrencyDefinition(bytes memory input)
         public
         pure
         returns (
             VerusObjects.CcurrencyDefinition memory ccurrencyDefinition
         )
    {
        uint32 nextOffset;
        uint8 nameStringLength;
        address parent;
        address launchSystemID;
        address systemID;
        address nativeCurrencyID;
        uint32 CCC_PREFIX_TO_PARENT = 4 + 4 + 20;
        uint32 CCC_ID_LEN = 20;
        uint32 CCC_NATIVE_OFFSET = CCC_ID_LEN + 4 + 4;

        nextOffset = CCC_PREFIX_TO_PARENT;

        assembly {
            parent := mload(add(input, nextOffset)) // this should be parent ID
            nextOffset := add(nextOffset, 1) // and after that...
            nameStringLength := mload(add(input, nextOffset)) // string length MAX 64 so will always be a byte
        }

        ccurrencyDefinition.parent = parent;

        bytes memory name = new bytes(nameStringLength);

        for (uint256 i = 0; i < nameStringLength; i++) {
            name[i] = input[i + nextOffset];
        }

        ccurrencyDefinition.name = string(name);
        nextOffset = nextOffset + nameStringLength + CCC_ID_LEN;

        assembly {
            launchSystemID := mload(add(input, nextOffset)) // this should be launchsysemID
            nextOffset := add(nextOffset, CCC_ID_LEN)
            systemID := mload(add(input, nextOffset)) // this should be systemID 
            nextOffset := add(nextOffset, CCC_NATIVE_OFFSET)
            nativeCurrencyID := mload(add(input, nextOffset)) //TODO:When example available to test, fix this
        }

        ccurrencyDefinition.launchSystemID = launchSystemID;
        ccurrencyDefinition.systemID = systemID;
        ccurrencyDefinition.nativeCurrencyID = nativeCurrencyID;
    }

    function simpleCurrencyDef(bytes memory input) public pure
                    returns (uint256, address)
    {
        uint32 nextOffset;
        uint8 nameStringLength;
        address systemID;
        address nativeCurrencyID;
        uint32 CCC_PREFIX_TO_PARENT = 4 + 4 + 20 + 1;
        uint32 CCC_ID_LEN = 20;
        uint32 CCC_NATIVE_OFFSET = CCC_ID_LEN + 4 + 4;

        uint256 destinationAndFlags;

        nextOffset = CCC_PREFIX_TO_PARENT;

        assembly {
            nameStringLength := mload(add(input, nextOffset)) // string length MAX 64 so will always be a byte
        }

        destinationAndFlags = nameStringLength > 19 ? 19 : nameStringLength; //first byte is length 

        for (uint32 i = 0; i < nameStringLength; i++) { //pack a max of 19 bytes of the id name into token name
            destinationAndFlags |= uint256(uint8(input[i + nextOffset])) << ((i+1)*8);
        }
        
        nextOffset = nextOffset + nameStringLength + CCC_ID_LEN;

        assembly {
            //   launchSystemID := mload(add(input, nextOffset)) // this should be launchsysemID
            nextOffset := add(nextOffset, CCC_ID_LEN)
            systemID := mload(add(input, nextOffset)) // this should be systemID 
            nextOffset := add(nextOffset, CCC_NATIVE_OFFSET)
            nativeCurrencyID := mload(add(input, nextOffset)) 
        }

        //if first 2 bytes blank then nativecurrency is empty
        if ((uint160(nativeCurrencyID) >> 144) & 0xffff == 0)
        {
            nativeCurrencyID = address(0);
        }
        else 
        {
            assembly {
                nativeCurrencyID := mload(add(add(input, nextOffset), 2) )
            }

        }

        destinationAndFlags |= uint256(VerusConstants.TOKEN_LAUNCH) << 160;

        if(systemID == VerusConstants.VEth)
        {
            destinationAndFlags |= uint256(VerusConstants.TOKEN_MAPPED_ERC20) << 160;
        }

        return (destinationAndFlags, nativeCurrencyID);

    }

        function deserializeTransfers(bytes calldata serializedData) public pure
        returns (VerusObjects.DeserializedObject memory)
    {
        

        bytes memory tempSerialized;
        VerusObjects.PackedSend[] memory tempTransfers = new VerusObjects.PackedSend[]((serializedData.length / 111) +1); //min size of transfer 222 bytes
        tempSerialized = serializedData;
        address tempaddress;
        uint64 amount;
        uint64 flags;
        uint8 destinationType;
        uint64 readerLen;
        uint8 ETHCounter; 
        uint8 currencyCounter;
        uint32 counter;
        uint256 nextOffset = 21;

        while (nextOffset <= tempSerialized.length) {
            
            assembly {
                tempaddress := mload(add(tempSerialized, nextOffset)) // skip version 0x01 (1 byte)
            }

            (amount, nextOffset)  = readVarint(tempSerialized, nextOffset);  //readvarint returns next idx position
            (flags , nextOffset) = readVarint(tempSerialized, nextOffset);

            tempTransfers[counter].currencyAndAmount = uint256(amount) << 160; //shift amount and pack
            tempTransfers[counter].currencyAndAmount |= uint256(uint160(tempaddress));

            nextOffset += 20; //skip feecurrency id always vETH, variint already 1 byte in so 19

            (amount, nextOffset) = readVarint(tempSerialized, nextOffset); //fees read into 'amount' but not used

            assembly {
                nextOffset := add(nextOffset, 1) 
                destinationType := mload(add(tempSerialized, nextOffset))
                nextOffset := add(nextOffset, 1) //skip feecurrency id always vETH
            }

            (readerLen, nextOffset) = readCompactSizeLE2(tempSerialized, nextOffset);    // get the length of the destination

            // if destination an address read 
            if(readerLen == 20)
            {
                if (tempaddress == VerusConstants.VEth)
                {
                    tempTransfers[counter].destinationAndFlags = uint256(VerusConstants.TOKEN_ETH_SEND) << 160;
                }
                else
                {
                    tempTransfers[counter].destinationAndFlags = uint256(VerusConstants.TOKEN_SEND) << 160;
                }

                assembly {
                    tempaddress := mload(sub(add(add(tempSerialized, nextOffset), readerLen), 1))
                }
                tempTransfers[counter].destinationAndFlags |= uint256(uint160(tempaddress));
            }
            else
            {
                bytes memory tempCurrency = serializedData[nextOffset - 1 : nextOffset + readerLen - 1];
                
                (tempTransfers[counter].destinationAndFlags, tempTransfers[counter].nativeCurrency) = 
                simpleCurrencyDef(tempCurrency);
            }

            nextOffset += readerLen ;

            if(destinationType & VerusConstants.FLAG_DEST_AUX == VerusConstants.FLAG_DEST_AUX )
            {
                 (readerLen, nextOffset) = readCompactSizeLE2(tempSerialized, nextOffset);    // get the length of the auxDest
                 uint arraySize = readerLen;
                 for (uint i = 0; i < arraySize; i++)
                 {
                     (readerLen, nextOffset) = readCompactSizeLE2(tempSerialized, nextOffset);    // get the length of the auxDest sub array
                     nextOffset += readerLen;
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

            if (address(uint160(tempTransfers[counter].currencyAndAmount)) == VerusConstants.VEth)
            {
                ETHCounter++;
            }

            if (destinationType  == VerusConstants.DEST_REGISTERCURRENCY)
            {
                currencyCounter++;
            }
            counter++;
            nextOffset += 20; //offsetready for next read (skip )

        }
        //pack 32Bit counter with 1 16bit and two 8bit numbers
        
        counter |= (uint32(ETHCounter) << 16);
        counter |= (uint32(currencyCounter) << 24);

        
        return VerusObjects.DeserializedObject(tempTransfers, counter);

    }
        
    function readVarint(bytes memory buf, uint idx) public pure returns (uint64 v, uint retidx) {

        uint8 b; // store current byte content

        for (uint i=0; i<10; i++) {
            b = uint8(buf[i+idx]);
            v = (v << 7) | b & 0x7F;
            if (b & 0x80 == 0x80)
                v++;
            else
            return (v, idx + i + 1);
        }
        revert(); // i=10, invalid varint stream
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
            assembly {
                oneByte := mload(add(incoming, offset))
            }
            uint16 twoByte = oneByte;
            offset++;
            assembly {
                oneByte := mload(add(incoming, offset))
            }
            return ((twoByte << 8) + oneByte, offset + 1);
        }
        return (0, offset);
    }

}