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
import "../MMR/VerusProof.sol";

contract VerusBridgeMaster {

    VerusNotarizer verusNotarizer;
    VerusBridge verusBridge;
    VerusInfo verusInfo;
    VerusBridgeStorage verusBridgeStorage;
    
    // Total amount of contracts.
    address[10] public contracts;
    bool firstSetup;

    //TODO: Contact one single owner. To upgrade to a multisig
    address contractOwner;
    
    // contract allows the contracts to be upgradable
    constructor(){
            contractOwner = msg.sender;      
    }
    
   function upgradeContract(VerusConstants.ContractType contractType, address _newContractAddress) public {
        
        //TODO: Make updating contract a multisig check across 3 notaries.
        assert(msg.sender == contractOwner);

        contracts[uint(contractType)] = _newContractAddress;

        if (contractType == VerusConstants.ContractType.TokenManager){
            verusBridge.setContracts(contracts);
            verusBridgeStorage.setContracts(contracts); 
            verusInfo.setContracts(contracts);  
        }
        else if (contractType == VerusConstants.ContractType.VerusSerializer){
            verusBridge.setContracts(contracts);
            verusNotarizer.setContract(_newContractAddress);
        }
        else if (contractType == VerusConstants.ContractType.VerusProof){
            verusBridge.setContracts(contracts);
        }
        else if (contractType == VerusConstants.ContractType.VerusCrossChainExport){
            verusBridge.setContracts(contracts);
        }
        else if (contractType == VerusConstants.ContractType.VerusNotarizer){
            verusNotarizer = VerusNotarizer(_newContractAddress); 
            verusBridge = VerusBridge(_newContractAddress);
            verusInfo.setContracts(contracts);
        }        
        else if (contractType == VerusConstants.ContractType.VerusBridge){
            verusBridge = VerusBridge(_newContractAddress);
            verusBridgeStorage.setContracts(contracts);      
        }
        else if (contractType == VerusConstants.ContractType.VerusInfo){
            verusInfo = VerusInfo(_newContractAddress);       
        }
        else if (contractType == VerusConstants.ContractType.ExportManager){
            verusBridge.setContracts(contracts);

        }
        else if (contractType == VerusConstants.ContractType.VerusBridgeStorage){
            verusBridgeStorage = VerusBridgeStorage(_newContractAddress);
            verusBridgeStorage.setContracts(contracts);   
        }

    }

    function setAllContracts(address[] memory contractsIn, VerusObjects.setupToken[] memory tokensToDeploy) public {

        assert(msg.sender == contractOwner);
        assert(!firstSetup);

        //once first contract set, bulk setting no longer allowed.
        if(contracts[0] == address(0)){
            for(uint i = 0; i < uint(VerusConstants.ContractType.LastIndex) - 1; i++ )
                contracts[i] = contractsIn[i]; 
        }
        
        // First set the referenced contracts 
        verusNotarizer = VerusNotarizer(contractsIn[uint(VerusConstants.ContractType.VerusNotarizer)]);
        verusBridge = VerusBridge(contractsIn[uint(VerusConstants.ContractType.VerusBridge)]);
        verusInfo = VerusInfo(contractsIn[uint(VerusConstants.ContractType.VerusInfo)]);
        verusBridgeStorage = VerusBridgeStorage(contractsIn[uint(VerusConstants.ContractType.VerusBridgeStorage)]);

        // Set contract(s) that are not set in their contructors.
        verusBridgeStorage.setContracts(contracts);

        // Launch currencey definitions that are known by the Verus contracts
        verusInfo.launchTokens(tokensToDeploy);
        firstSetup = true;

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


}