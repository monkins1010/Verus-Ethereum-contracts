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
import "../VerusBridge/VerusSerializer.sol";

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
    address[] public pendingContracts;

    address contractOwner;
    VerusObjects.pendingUpgradetype[] pendingContractsSignatures;
    uint8 constant TYPE_CONTRACT = 1;
    uint8 constant TYPE_REVOKE = 2;
    uint8 constant TYPE_RECOVER = 3;

    //global store of salts to stop a repeat attack
    mapping (bytes32 => bool) saltsUsed;
    
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
            tokenManager.setContracts(_newContractAddress[uint(VerusConstants.ContractType.VerusSerializer)], 
                                     _newContractAddress[uint(VerusConstants.ContractType.VerusBridge)]);
        } 
       
        // TODO: Reactivate when multisig active contractOwner = address(0);  //Blow the fuse i.e. make it one time only.
    }

    function upgradeContracts(VerusObjects.upgradeInfo memory _newContractPackage) public {

        require(msg.sender == contractOwner);
        // TODO: Reactivate // if (!checkMultiSigContracts(_newContractPackage)) return; 

        address[12] memory tempcontracts;

        for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++) 
        {
            tempcontracts[i] = _newContractPackage.contracts[i];
        }

               
        if(tempcontracts[uint(VerusConstants.ContractType.TokenManager)] != address(tokenManager)) {
            tokenManager = TokenManager(tempcontracts[uint(VerusConstants.ContractType.TokenManager)]);
            verusBridge.setContracts(tempcontracts);
            verusBridgeStorage.setContracts(tempcontracts);
            verusInfo.setContracts(tempcontracts);
            exportManager.setContract(tempcontracts[uint(VerusConstants.ContractType.TokenManager)]);
            tokenManager.setContracts(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)], 
                        tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]); 
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
            tokenManager.setContracts(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)], 
                        tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]); 
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusInfo)] != address(verusInfo)) {
            verusBridgeMaster.setContracts(tempcontracts);
        }
        
        if(tempcontracts[uint(VerusConstants.ContractType.ExportManager)] != address(exportManager))  {    
            verusBridge.setContracts(tempcontracts);   
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)] != contracts[uint(VerusConstants.ContractType.VerusSerializer)])  {   
           verusCrossChainExport.setContract(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)]);
           tokenManager.setContracts(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)], 
                                    tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]);
           verusBridge.setContracts(tempcontracts);  

        }

        // Once all the contracts are set copy the new values to the global
        for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++) 
        {
            contracts[i] = _newContractPackage.contracts[i];
        }

        delete pendingContracts;
        
    }

    function revoke(VerusObjects.upgradeInfo memory _newContractPackage) public {

        if (!checkMultiSigContracts(_newContractPackage)) return; 
        verusNotarizerStorage.setLastNotarizationHeight(uint32(0xffffffff));
        delete pendingContractsSignatures;
    
    }

    function recover(VerusObjects.upgradeInfo memory _newContractPackage) public {

        if (!checkMultiSigContracts(_newContractPackage)) return; 
        verusNotarizerStorage.setLastNotarizationHeight(_newContractPackage.recoverHeight);
        delete pendingContractsSignatures;
    
    }

    // TODO: change function to be a private
    function checkMultiSigContracts(VerusObjects.upgradeInfo memory _newContractPackage) public returns(bool)
    {
        bytes memory be; 
        bytes32 hashValue;


        require(saltsUsed[_newContractPackage.salt] == false, "salt Already used");
        saltsUsed[_newContractPackage.salt] = true;

        if(_newContractPackage.upgradeType == TYPE_CONTRACT)
        {
            require(_newContractPackage.contracts.length == contracts.length, "Inputted contracts wrong length");
            //concatenate the old contract values
            for (uint j = 0; j < contracts.length; j++)
            {
                be = abi.encodePacked(be, contracts[j]);

                // If 
                if(pendingContracts.length < 11)
                {
                    pendingContracts[j] = contracts[j];
                }
            }

            //concatenate the old contract values + new valeus
            for (uint k = 0; k < _newContractPackage.contracts.length; k++ )
            {
                be = abi.encodePacked(be, _newContractPackage.contracts[k]);
                require(pendingContracts[k] == contracts[k],"Upgrade contracts do not match");
            }

            be = abi.encodePacked(be, _newContractPackage.salt);
        }
        else if (_newContractPackage.upgradeType == TYPE_REVOKE || _newContractPackage.upgradeType == TYPE_REVOKE)
        {
            be = abi.encodePacked(uint8(_newContractPackage.upgradeType), _newContractPackage.salt);
        }
        else 
        {
            revert("Invalid upgrade type");
        }

        VerusSerializer verusSerializer = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]);

        hashValue = sha256(abi.encodePacked(verusSerializer.writeCompactSize(be.length),be));
        hashValue = sha256(abi.encodePacked(uint8(19),hex"5665727573207369676e656420646174613a0a", hashValue)); // prefix = 19(len) + "Verus signed data:\n"

        if (recoverSigner(hashValue, _newContractPackage._vs - 4, _newContractPackage._rs, 
                        _newContractPackage._ss) != verusNotarizer.notaryAddressMapping(_newContractPackage.notaryAddress))
        {
            revert("Invalid notary signer");  
        }
        
        return setPendingUpgrade(_newContractPackage.notaryAddress, _newContractPackage.upgradeType);
 
    }

    function setPendingUpgrade(address notaryAddress, uint8 upgradeType) private returns (bool) {
  
        // build the pending upgrade array until it is complete with enough signatures of the same type of upgrade.
        if(pendingContractsSignatures.length == 0)
        {
            pendingContractsSignatures.push(VerusObjects.pendingUpgradetype(notaryAddress, upgradeType));
        }
        else
        {
            for (uint i = 0; i < (pendingContractsSignatures.length + 1); i++)
            {
                if(pendingContractsSignatures[i].notaryID != notaryAddress && pendingContractsSignatures[i].notaryID == address(0))
                {
                    pendingContractsSignatures.push(VerusObjects.pendingUpgradetype(notaryAddress, upgradeType));
                }
                else if (pendingContractsSignatures[i].notaryID == notaryAddress && 
                pendingContractsSignatures[i].upgradeType == upgradeType)
                {
                    // Delete the array and start the updrade again
                    delete pendingContractsSignatures;
                    return false;
                }

            }
        }
        
        // Return true if all notaries signed
        return pendingContractsSignatures.length >= verusNotarizer.notaryCount();

    }

    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {

        return ecrecover(_h, _v, _r, _s);
    }

    function getBridgeAddress() public view returns (address)
    {
        return contracts[uint(VerusConstants.ContractType.VerusBridge)];
    }
}