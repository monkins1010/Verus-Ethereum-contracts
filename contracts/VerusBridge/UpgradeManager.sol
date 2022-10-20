// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

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
    VerusObjects.pendingUpgradetype[] public pendingContractsSignatures;
    uint8 constant TYPE_CONTRACT = 1;
    uint8 constant TYPE_REVOKE = 2;
    uint8 constant TYPE_RECOVER = 3;
    uint8 constant NUM_ADDRESSES_FOR_REVOKE = 3;

    //global store of salts to stop a repeat attack
    mapping (bytes32 => bool) saltsUsed;

    event contractUpdated(bool);
    
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

    function upgradeContracts(VerusObjects.upgradeInfo memory _newContractPackage) public returns (uint8) {

        //require(msg.sender == contractOwner);
        if (!checkMultiSigContracts(_newContractPackage)) return 1; 

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
            verusNotarizer = VerusNotarizer(tempcontracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
            verusBridgeMaster.setContracts(tempcontracts);
            verusInfo.setContracts(tempcontracts);
            verusNotarizerStorage.setContracts(tempcontracts);
            verusProof.setContracts(tempcontracts);
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusBridge)] != address(verusBridge)) {
            verusBridge = VerusBridge(tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]);
            verusBridgeMaster.setContracts(tempcontracts);
            verusBridgeStorage.setContracts(tempcontracts);
            verusNotarizerStorage.setContracts(tempcontracts);  
            tokenManager.setContracts(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)], 
                        tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]); 
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusInfo)] != address(verusInfo)) {
            verusBridgeMaster.setContracts(tempcontracts);
            verusInfo = VerusInfo(tempcontracts[uint(VerusConstants.ContractType.VerusInfo)]);
        }
        
        if(tempcontracts[uint(VerusConstants.ContractType.ExportManager)] != address(exportManager))  {    
            exportManager = ExportManager(tempcontracts[uint(VerusConstants.ContractType.ExportManager)]);
            verusBridge.setContracts(tempcontracts);   
        }

        if(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)] != contracts[uint(VerusConstants.ContractType.VerusSerializer)])  {   
            verusCrossChainExport.setContract(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)]);
            tokenManager.setContracts(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)], 
                                    tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]);
            verusBridge.setContracts(tempcontracts);  
            verusProof.setContracts(tempcontracts);
            verusNotarizer.setContract(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)]);
        }

        // Once all the contracts are set copy the new values to the global
        for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++) 
        {
            contracts[i] = _newContractPackage.contracts[i];
        }

        delete pendingContracts;
        delete pendingContractsSignatures;
        emit contractUpdated(true);
        return 2;
        
    }

    function recoverString(bytes memory be, uint8 vs, bytes32 rs, bytes32 ss) public view returns (address)
    {
        bytes32 hashValue;

        VerusSerializer verusSerializer = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]);

        hashValue = sha256(abi.encodePacked(verusSerializer.writeCompactSize(be.length),be)); //NOTE: This maybe always 64 bytes, check!
        hashValue = sha256(abi.encodePacked(uint8(19),hex"5665727573207369676e656420646174613a0a", hashValue)); // prefix = 19(len) + "Verus signed data:\n"

        return recoverSigner(hashValue, vs - 4, rs, ss);

    }

    function revoke(VerusObjects.revokeInfo memory _revokePacket) public returns (bool) {

        bytes memory be; 

        require(saltsUsed[_revokePacket.salt] == false, "salt Already used");
        saltsUsed[_revokePacket.salt] = true;

        be = bytesToString(abi.encodePacked(_revokePacket.salt));

        address signer = recoverString(be, _revokePacket._vs, _revokePacket._rs, _revokePacket._ss);
        
        VerusObjects.notarizer memory notary;
        // get the notarys status from the mapping using its Notary i-address to check if it is valid.
        (notary.main, notary.recovery, notary.state) = verusNotarizer.notaryAddressMapping(_revokePacket.notaryID);

        if (notary.main != signer || notary.state == VerusConstants.NOTARY_REVOKED)
        {
            emit contractUpdated(false);
            return false;  
        }

        verusNotarizer.updateNotarizer(_revokePacket.notaryID, address(0), notary.recovery, VerusConstants.NOTARY_REVOKED);
        emit contractUpdated(true);

        //Incase of Notary trying upgrade
        delete pendingContracts;
        delete pendingContractsSignatures;

        return true;
    
    }
    function recover(VerusObjects.upgradeInfo memory _newContractPackage) public returns (uint8) {

        if (!checkMultiSigContracts(_newContractPackage)) return 1; 
        verusNotarizer.updateNotarizer(_newContractPackage.contracts[0], _newContractPackage.contracts[1], 
        _newContractPackage.contracts[2], VerusConstants.NOTARY_VALID);
        delete pendingContracts;
        delete pendingContractsSignatures;
        return 2;
    
    }

    // TODO: change function to be only callable from notaries
    function checkMultiSigContracts(VerusObjects.upgradeInfo memory _newContractPackage) public returns(bool)
    {
        bytes memory be; 

        require(saltsUsed[_newContractPackage.salt] == false, "salt Already used");
        saltsUsed[_newContractPackage.salt] = true;

        uint contractArrayLen;

        if(_newContractPackage.upgradeType == TYPE_CONTRACT)
        {
            contractArrayLen = contracts.length;
        }
        else if(_newContractPackage.upgradeType == TYPE_REVOKE || _newContractPackage.upgradeType == TYPE_RECOVER)
        {
            contractArrayLen = NUM_ADDRESSES_FOR_REVOKE;
        }
        
        require(contractArrayLen == _newContractPackage.contracts.length, "Input contracts wrong length");
        
        // if start of a new upgrade then set the pending contracts to either upgrade contracts, or Notary modifcation

        for (uint j = 0; j < contractArrayLen; j++)
        {
            be = abi.encodePacked(be, _newContractPackage.contracts[j]);
            
            if(pendingContracts.length < contractArrayLen)
            {
                pendingContracts.push(_newContractPackage.contracts[j]);
            }
            else
            {
                require(pendingContracts[j] == _newContractPackage.contracts[j],"Upgrade contracts do not match");
            }
        }

        be = bytesToString(abi.encodePacked(be, uint8(_newContractPackage.upgradeType), _newContractPackage.salt));

        address signer = recoverString(be, _newContractPackage._vs, _newContractPackage._rs, _newContractPackage._ss);

        VerusObjects.notarizer memory notary;
        // get the notarys status from the mapping using its Notary i-address to check if it is valid.
        (notary.main, notary.recovery, notary.state) = verusNotarizer.notaryAddressMapping(_newContractPackage.notarizerID);

        if (notary.state != VerusConstants.NOTARY_VALID || notary.recovery != signer)
        {
            revert("Invalid notary signer");  
        }
        
        return setPendingUpgrade(_newContractPackage.notarizerID, _newContractPackage.upgradeType);
 
    }

    function bytesToString (bytes memory input) public pure returns (bytes memory output)
    {
        bytes memory _string = new bytes(input.length * 2);
        bytes memory HEX = "0123456789abcdef";

        for(uint i = 0; i < input.length; i++) 
        {
            _string[i*2] = HEX[uint8(input[i] >> 4)];
            _string[1+i*2] = HEX[uint8(input[i] & 0x0f)];
        }
        return _string;
    }

    function setPendingUpgrade(address notaryAddress, uint8 upgradeType) public returns (bool) { //TODO: change to private
  
        // build the pending upgrade array until it is complete with enough signatures.
        if(pendingContractsSignatures.length == 0)
        {
            pendingContractsSignatures.push(VerusObjects.pendingUpgradetype(notaryAddress, upgradeType));
        }
        else
        {
            for (uint i = 0; i < (pendingContractsSignatures.length); i++)
            {
                if (pendingContractsSignatures[i].notaryID == notaryAddress || pendingContractsSignatures[i].upgradeType != upgradeType)
                {
                    revert("Notary invalid or mixed upgrade type"); 
                }
                VerusObjects.notarizer memory notary;

                (notary.main, notary.recovery, notary.state) = verusNotarizer.notaryAddressMapping(pendingContractsSignatures[i].notaryID);

                // If any notary has become invalid, invalidate pending upgrade and start again
                if (notary.state != VerusConstants.NOTARY_VALID)
                {
                    delete pendingContracts;
                    delete pendingContractsSignatures;
                    return false;
                }
            }

            pendingContractsSignatures.push(VerusObjects.pendingUpgradetype(notaryAddress, upgradeType));

        }

        // Return true if majority of notarized have transacted.
        return pendingContractsSignatures.length >= ((verusNotarizer.currentNotariesLength() >> 1) + 1 );

    }

    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {

        return ecrecover(_h, _v, _r, _s);
    }

    function getBridgeAddress() public view returns (address)
    {
        return contracts[uint(VerusConstants.ContractType.VerusBridge)];
    }
}