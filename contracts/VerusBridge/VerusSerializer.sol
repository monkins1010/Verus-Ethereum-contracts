// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 < 0.9.0;
pragma experimental ABIEncoderV2;   
import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";

contract VerusSerializer {

    //hashing functions

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
        return abi.encodePacked(serializeUint8(ctd.destinationtype),writeCompactSize(20),serializeAddress(ctd.destinationaddress));
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
           
        if((ct.flags & 0x400)>0) output = abi.encodePacked(output,serializeAddress(ct.secondreserveid));           
         //see if its got a cross_system flag
        if((ct.flags & 0x40)>0) output = abi.encodePacked(output,serializeAddress(ct.destsystemid));
        
        return output;
    }
    
    function serializeCReserveTransfers(VerusObjects.CReserveTransfer[] memory _bts,bool includeSize) public pure returns(bytes memory){
        bytes memory inProgress;
        
        if(includeSize) inProgress =writeCompactSize(_bts.length);
        
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
            writeVarInt(_ccce.sourceheightstart),
            writeVarInt(_ccce.sourceheightend),
            serializeAddress(_ccce.destinationsystemid),
            serializeAddress(_ccce.destinationcurrencyid));
        bytes memory part2 = abi.encodePacked(serializeUint32(_ccce.numinputs),
            serializeCCurrencyValueMaps(_ccce.totalamounts),
            serializeCCurrencyValueMaps(_ccce.totalfees),
            flipArray(serializeBytes32(_ccce.hashtransfers)),
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

}