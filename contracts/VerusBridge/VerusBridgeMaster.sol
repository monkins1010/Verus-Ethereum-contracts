// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusBridgeStorage.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusBridge.sol";
import "./VerusInfo.sol";
import "../VerusNotarizer/VerusNotarizerStorage.sol";

contract VerusBridgeMaster {

    VerusNotarizer verusNotarizer;
    VerusBridge verusBridge;
    VerusInfo verusInfo;
    VerusBridgeStorage verusBridgeStorage;
    VerusNotarizerStorage verusNotarizerStorage;

    address upgradeContract;
    
  
    constructor(address upgradeContractAddress)
    {
        upgradeContract = upgradeContractAddress;      
    }
    
   function setContracts(address[12] memory contracts) public {
   
        assert(msg.sender == upgradeContract);
        
        if(contracts[uint(VerusConstants.ContractType.VerusNotarizer)] != address(verusNotarizer)) 
        {
            verusNotarizer = VerusNotarizer(contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
        }
         
        if(contracts[uint(VerusConstants.ContractType.VerusBridge)] != address(verusBridge)) 
        {       
            verusBridge = VerusBridge(contracts[uint(VerusConstants.ContractType.VerusBridge)]);
        }

        if(contracts[uint(VerusConstants.ContractType.VerusInfo)] != address(verusInfo)) 
        { 
            verusInfo = VerusInfo(contracts[uint(VerusConstants.ContractType.VerusInfo)]);
        }

        if(contracts[uint(VerusConstants.ContractType.VerusBridgeStorage)] != address(verusBridgeStorage)) 
        {         
            verusBridgeStorage = VerusBridgeStorage(contracts[uint(VerusConstants.ContractType.VerusBridgeStorage)]);
        }
                
        if(contracts[uint(VerusConstants.ContractType.VerusNotarizerStorage)] != address(verusNotarizerStorage)) 
        { 
            verusNotarizerStorage = VerusNotarizerStorage(contracts[uint(VerusConstants.ContractType.VerusNotarizerStorage)]);
        }
    }
    
    /** VerusBridge pass through functions **/
    function export(VerusObjects.CReserveTransfer memory _transfer) public payable {
      
        verusBridge.export(_transfer, msg.value, msg.sender );
    }

    function checkImport(bytes32 _imports) public view returns(bool){
        return verusBridgeStorage.processedTxids(_imports);
    }

    function submitImports(VerusObjects.CReserveTransferImport[] memory _imports) public {
        verusBridge.submitImports(_imports);
    }

    function getReadyExportsByRange(uint _startBlock, uint _endBlock) public view 
        returns(VerusObjects.CReserveTransferSet[] memory){
        return verusBridge.getReadyExportsByRange(_startBlock,_endBlock);
    }

    /** VerusNotarizer pass through functions **/

    function isPoolAvailable() public view returns(bool){
        return verusNotarizer.poolAvailable();
    }

    function getLastProofRoot() public view returns(VerusObjectsNotarization.CProofRoot memory){
        return verusNotarizerStorage.getLastProofRoot();
    }

    function lastBlockHeight() public view returns(uint32){
        return verusNotarizerStorage.lastBlockHeight();
    }

    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization,
        uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddress
        ) public returns(bool){
            return verusNotarizer.setLatestData(_pbaasNotarization,_vs,_rs,_ss,blockheights,notaryAddress);
    }

    /** VerusInfo pass through functions **/

     function getinfo() public view returns(bytes memory){
         return verusInfo.getinfo();
     }

     function sendEth(uint256 _ethAmount, address payable _ethAddress) public {
         //only callable by verusbridge contract
        assert( msg.sender == address(verusBridge));
        _ethAddress.transfer(_ethAmount);
     }

     function getcurrency(address _currencyid) public view returns(bytes memory){

        return verusInfo.getcurrency(_currencyid);

     }

    function getLastimportHeight() public view returns (uint){
        return verusBridgeStorage.lastTxImportHeight();
    }

}