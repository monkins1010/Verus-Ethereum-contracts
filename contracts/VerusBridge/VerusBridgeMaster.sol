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
    
   function upgradeContract(VerusConstants.ContractType contractType, address[] memory _newContractAddress) public {
        //TODO: Make updating contract a multisig check across 3 notaries.
        assert(msg.sender == contractOwner);
        if (!firstSetup){
            for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++) {
                contracts[i] = _newContractAddress[i];
            }
            verusNotarizer = VerusNotarizer(_newContractAddress[uint(VerusConstants.ContractType.VerusNotarizer)]);
            verusBridge = VerusBridge(_newContractAddress[uint(VerusConstants.ContractType.VerusBridge)]);
            verusInfo = VerusInfo(_newContractAddress[uint(VerusConstants.ContractType.VerusInfo)]);
            verusBridgeStorage = VerusBridgeStorage(_newContractAddress[uint(VerusConstants.ContractType.VerusBridgeStorage)]);
            verusBridgeStorage.setContracts(contracts); 
            firstSetup = true;
        } else {


        if (contractType == VerusConstants.ContractType.TokenManager){
            verusBridge.setContracts(contracts);
            verusBridgeStorage.setContracts(contracts); 
            verusInfo.setContracts(contracts);  
        }
        else if (contractType == VerusConstants.ContractType.VerusSerializer){
            verusBridge.setContracts(contracts);
            verusNotarizer.setContract(_newContractAddress[0]);
        }
        else if (contractType == VerusConstants.ContractType.VerusProof){
            verusBridge.setContracts(contracts);
        }
        else if (contractType == VerusConstants.ContractType.VerusCrossChainExport){
            verusBridge.setContracts(contracts);
        }
        else if (contractType == VerusConstants.ContractType.VerusNotarizer){
            verusNotarizer = VerusNotarizer(_newContractAddress[0]); 
            verusBridge = VerusBridge(_newContractAddress[0]);
            verusInfo.setContracts(contracts);
        }        
        else if (contractType == VerusConstants.ContractType.VerusBridge){
            verusBridge = VerusBridge(_newContractAddress[0]);
            verusBridgeStorage.setContracts(contracts);      
        }
        else if (contractType == VerusConstants.ContractType.VerusInfo){
            verusInfo = VerusInfo(_newContractAddress[0]);       
        }
        else if (contractType == VerusConstants.ContractType.ExportManager){
            verusBridge.setContracts(contracts);

        }
        else if (contractType == VerusConstants.ContractType.VerusBridgeStorage){
            verusBridgeStorage = VerusBridgeStorage(_newContractAddress[0]);
            verusBridgeStorage.setContracts(contracts);   
        }

        }
    }

    
    /** VerusBridge pass through functions **/
    function export(VerusObjects.CReserveTransfer memory _transfer) public payable {
      
        verusBridge.export(_transfer, msg.value, msg.sender );
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
        return verusNotarizer.isPoolAvailable(_address);

    }

    function getLastProofRoot() public view returns(VerusObjectsNotarization.CProofRoot memory){
        return verusBridgeStorage.getLastProofRoot();
    }

    function lastBlockHeight() public view returns(uint32){
        return verusBridgeStorage.lastBlockHeight();
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
        assert( msg.sender == address(verusBridge));
        _ethAddress.transfer(_ethAmount);
     }


}