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

    // uses the varint encoding from Bitcoin script pushes
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
            output = abi.encodePacked(uint8(253),uint16(newNumber));
        }
        else if (newNumber <= 0xFFFFFFFF)
        {   
            output = abi.encodePacked(uint8(254),uint32(newNumber));
        }
        else
        {
            output = abi.encodePacked(uint8(255),uint64(newNumber));
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
            writeVarInt(uint256(_cccs.initialsupply)),
            writeVarInt(uint256(_cccs.emitted)),
            writeVarInt(uint256(_cccs.supply))
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
            serializeInt32(_ccce.firstinput),bytes1(0x00));
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
            nativeCurrencyID := mload(add(input, nextOffset)) //TODO: daemon serilaization to be changed this should be nativeCurrencyID
        }

        ccurrencyDefinition.launchSystemID = launchSystemID;
        ccurrencyDefinition.systemID = systemID;
        ccurrencyDefinition.nativeCurrencyID = nativeCurrencyID;
    }

}