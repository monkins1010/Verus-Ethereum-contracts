// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusBridgeStorage.sol";
import "../VerusBridge/VerusBridgeMaster.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusBridge.sol";
import "./VerusInfo.sol";
import "./TokenManager.sol";
import "../MMR/VerusProof.sol";
import "../VerusNotarizer/VerusNotarizerStorage.sol";
import "./ExportManager.sol";
import "../VerusBridge/VerusCrossChainExport.sol";

contract UpgradeManager {

    TokenManager tokenManager;        
    VerusProof verusProof;
    VerusNotarizer verusNotarizer;
    VerusBridge verusBridge;
    VerusInfo verusInfo;
    ExportManager exportManager;
    VerusBridgeStorage verusBridgeStorage;
    VerusNotarizerStorage verusNotarizerStorage;
    VerusBridgeMaster verusBridgeMaster;
    VerusCrossChainExport verusCrossChainExport;
            
     // Total amount of contracts.
    address[12] public contracts;

     address contractOwner;
    

    constructor()
    {
        contractOwner = msg.sender;      
    }
    
   function setInitialContracts(address[] memory _newContractAddress) public {
    
        //One time set of contracts for all       
        require(msg.sender == contractOwner);
        if (contracts[0] == address(0)){

            for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++) 
            {
                contracts[i] = _newContractAddress[i];
            }

            tokenManager = TokenManager(contracts[uint(VerusConstants.ContractType.TokenManager)]);
            verusProof = VerusProof(contracts[uint(VerusConstants.ContractType.VerusProof)]); 
            verusNotarizer = VerusNotarizer(_newContractAddress[uint(VerusConstants.ContractType.VerusNotarizer)]);
            verusBridge = VerusBridge(_newContractAddress[uint(VerusConstants.ContractType.VerusBridge)]);
            verusInfo = VerusInfo(_newContractAddress[uint(VerusConstants.ContractType.VerusInfo)]);
            exportManager = ExportManager(contracts[uint(VerusConstants.ContractType.ExportManager)]);
            verusCrossChainExport = VerusCrossChainExport(_newContractAddress[uint(VerusConstants.ContractType.VerusCrossChainExport)]);
            
            verusBridgeStorage = VerusBridgeStorage(_newContractAddress[uint(VerusConstants.ContractType.VerusBridgeStorage)]);
            verusNotarizerStorage = VerusNotarizerStorage(_newContractAddress[uint(VerusConstants.ContractType.VerusNotarizerStorage)]);
            verusBridgeMaster = VerusBridgeMaster(_newContractAddress[uint(VerusConstants.ContractType.VerusBridgeMaster)]);

            verusBridgeStorage.setContracts(contracts); 
            verusNotarizerStorage.setContracts(contracts); 
            verusBridgeMaster.setContracts(contracts); 

        } 
        //Blow the fuse
        contractOwner = address(0);
    }

    function upgradeContracts(VerusObjects.upgradeContracts[] memory _newContractPackage) public {

        require(msg.sender == contractOwner);
      //TODO:Reactivate // require (checkMultiSig(_newContractPackage));

        address[12] memory tempcontracts;

        for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++) 
            {
                tempcontracts[i] = _newContractPackage[0].contracts[i];
            }

               
        if(tempcontracts[uint(VerusConstants.ContractType.TokenManager)] != address(tokenManager)) {
            tokenManager = TokenManager(tempcontracts[uint(VerusConstants.ContractType.TokenManager)]);
            verusBridge.setContracts(tempcontracts);
            verusBridgeStorage.setContracts(tempcontracts);
            verusInfo.setContracts(tempcontracts);
            exportManager.setContract(tempcontracts[uint(VerusConstants.ContractType.TokenManager)]);
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusProof)] != address(verusProof)) {
            verusProof = VerusProof(contracts[uint(VerusConstants.ContractType.VerusProof)]); 
            verusBridge.setContracts(tempcontracts);             
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusNotarizer)] != address(verusNotarizer)) {
            verusProof = VerusProof(contracts[uint(VerusConstants.ContractType.VerusProof)]);
            verusBridgeMaster.setContracts(tempcontracts);
            verusInfo.setContracts(tempcontracts);
            verusNotarizerStorage.setContracts(tempcontracts);
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusBridge)] != address(verusBridge)) {
            verusBridgeMaster.setContracts(tempcontracts);
            verusBridgeStorage.setContracts(tempcontracts);
            verusNotarizerStorage.setContracts(tempcontracts);   
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusInfo)] != address(verusInfo)) {
            verusBridgeMaster.setContracts(tempcontracts);
        }
        
        if(tempcontracts[uint(VerusConstants.ContractType.ExportManager)] != address(exportManager))  {    
            verusBridge.setContracts(tempcontracts);   
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)] != contracts[uint(VerusConstants.ContractType.VerusSerializer)])  {   
           verusCrossChainExport.setContract(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)]);
           tokenManager.setContract(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)]);
           verusBridge.setContracts(tempcontracts);  

        }

        // Once all the contracts are set copy the new values to the global
        for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++) 
        {
            contracts[i] = _newContractPackage[0].contracts[i];
        }
        
    }

    function checkMultiSig(VerusObjects.upgradeContracts[] memory _newContractPackage) public view returns(bool)
    {
        require(_newContractPackage.length >= uint256(verusNotarizer.notaryCount()), "Not enough notary signatures provided");
        require(_newContractPackage[0].contracts.length == contracts.length, "Inputted contracts wrong length");

        bytes memory be; 
        bytes32 hashValue;
        
        for (uint i = 0; i< _newContractPackage.length; i++ )
        {
            //concatenate the old contract values
            for (uint j = 0; j< contracts.length; j++ )
            {
                be = abi.encodePacked(be, contracts[j]);
            }

            //concatenate the old contract values + new valeus
            for (uint k = 0; k< _newContractPackage[i].contracts.length; k++ )
            {
                be = abi.encodePacked(be, _newContractPackage[i].contracts[k]);
            }
            
            hashValue = sha256(be);

            hashValue = sha256(abi.encodePacked(hex"5665727573207369676e656420646174613a0a",hashValue)); // prefix = "Verus signed data:\n"

            if (recoverSigner(hashValue, _newContractPackage[i]._vs - 4, _newContractPackage[i]. _rs, 
                            _newContractPackage[i]._ss) != verusNotarizer.notaryAddressMapping(_newContractPackage[i].notaryAddress))
            {
                revert("Invalid notary signer");  
            }

        }
        return true;

    }

    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {

        return ecrecover(_h, _v, _r, _s);
    }

    function getBridgeAddress() public view returns (address)
    {
        return contracts[uint(VerusConstants.ContractType.VerusBridge)];
    }
}