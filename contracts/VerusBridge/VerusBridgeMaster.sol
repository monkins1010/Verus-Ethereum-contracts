// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusBridgeStorage.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusBridge.sol";
import "./VerusInfo.sol";
import "./TokenManager.sol";

contract VerusBridgeMaster {

    //declare the contracts and have it return the contract addresses

    TokenManager tokenManager;
    VerusNotarizer verusNotarizer;
    VerusBridge verusBridge;
    VerusInfo verusInfo;
    VerusBridgeStorage verusBridgeStorage;
    
    // Total amount of contracts.
    address[8] contracts;

    //temporary placeholder for testing purposes
    address contractOwner;
    
  
    //contract allows the contracts to be set and reset
    constructor(){
            contractOwner = msg.sender;      
    }
    
    /** get and set functions, sets to be performed by the notariser **/
    function setContractAddress(VerusConstants.ContractType contractType, address _newContractAddress) public {
        
        //TODO: Make updating contract a multisig check across 3 notaries.
        assert(msg.sender == contractOwner);

        contracts[uint(contractType)] = _newContractAddress;

        if(contractType == VerusConstants.ContractType.VerusNotarizer){
            verusNotarizer = VerusNotarizer(_newContractAddress);       
        }        
        else if(contractType == VerusConstants.ContractType.VerusBridge){
            verusBridge = VerusBridge(_newContractAddress);
            verusBridgeStorage.setContractAddress(VerusConstants.ContractType.VerusBridge, _newContractAddress);       
        }
        else if(contractType == VerusConstants.ContractType.VerusInfo){
            verusInfo = VerusInfo(_newContractAddress);       
        }
        else if(contractType == VerusConstants.ContractType.TokenManager){
            tokenManager = TokenManager(_newContractAddress);
        }
        else if(contractType == VerusConstants.ContractType.VerusBridgeStorage){
            verusBridgeStorage = VerusBridgeStorage(_newContractAddress);
            verusBridgeStorage.setContractAddress(VerusConstants.ContractType.VerusBridgeStorage, _newContractAddress);   
        }
    }

    function setAllContracts(address[] memory contractsIn) public {

        assert(msg.sender == contractOwner);

        //once first contract set, bulk setting no longer allowed.
        if(contracts[0] == address(0)){
            for(uint i = 0; i < uint(VerusConstants.ContractType.LastIndex) - 1; i++ )
                contracts[i] = contractsIn[i]; 
        }
        
        // First set the referenced contracts 
        tokenManager = TokenManager(contractsIn[uint(VerusConstants.ContractType.VerusSerializer)]);
        verusNotarizer = VerusNotarizer(contractsIn[uint(VerusConstants.ContractType.VerusNotarizer)]);
        verusBridge = VerusBridge(contractsIn[uint(VerusConstants.ContractType.VerusBridge)]);
        verusInfo = VerusInfo(contractsIn[uint(VerusConstants.ContractType.VerusInfo)]);
        verusBridgeStorage = VerusBridgeStorage(contractsIn[uint(VerusConstants.ContractType.VerusBridgeStorage)]);
        
        // Set all contracts that are not set in their contructors.
        verusBridgeStorage.setContractAddress(VerusConstants.ContractType.VerusBridge, contractsIn[uint(VerusConstants.ContractType.VerusInfo)]);
        verusBridgeStorage.setContractAddress(VerusConstants.ContractType.TokenManager, contractsIn[uint(VerusConstants.ContractType.TokenManager)]);
        

    }
    
    /** returns the address of each contract to be used by the sub contracts **/
    function getContractAddress(VerusConstants.ContractType contractType) public view returns(address contractAddress){
        
        contractAddress = contracts[uint(contractType)];

    }

    function isSenderBridgeContract(address sender) private view {

        assert( sender == address(verusBridge));
    }

    /** VerusBridge pass through functions **/
    function export(VerusObjects.CReserveTransfer memory _transfer) public payable {
        uint256 ethAmount = msg.value;
        verusBridge.export(_transfer, ethAmount);
    }

    function checkImports(bytes32[] memory _imports) public view returns(bytes32[] memory){
        return verusBridge.checkImports(_imports);
    }

    function submitImports(VerusObjects.CReserveTransferImport[] memory _imports) public {
        verusBridge.submitImports(_imports);
    }

    function getReadyExportsByRange(uint _startBlock, uint _endBlock) public view 
        returns(VerusObjects.CReserveTransferSet[] memory){
        return verusBridge.getReadyExportsByRange(_startBlock,_endBlock);
    }

  

    /** VerusNotarizer pass through functions **/

    function poolAvailable(address _address) public view returns(bool){
        uint32 heightAvailable = verusNotarizer.poolAvailable(_address);
        return heightAvailable != 0 && heightAvailable < block.number;
    }

    function getLastProofRoot() public view returns(VerusObjectsNotarization.CProofRoot memory){
        return verusNotarizer.getLastProofRoot();
    }

    function lastBlockHeight() public view returns(uint32){
        return verusNotarizer.lastBlockHeight();
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

     function getinfo() public view returns(VerusObjects.infoDetails memory){
         return verusInfo.getinfo();
     }

     function sendEth(uint256 _ethAmount, address payable _ethAddress) public {
         //only callable by verusbridge contract
        isSenderBridgeContract(msg.sender);
        _ethAddress.transfer(_ethAmount);
     }

    function launchTokens(VerusObjects.setupToken[] memory tokensToDeploy) public  {
            
            assert(msg.sender == contractOwner);
            tokenManager.launchTokens(tokensToDeploy);

    }


}