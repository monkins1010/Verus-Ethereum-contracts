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
import "../VerusNotarizer/NotarizationSerializer.sol";

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
    NotarizationSerializer notarizationSerializer;
            
    // Total amount of contracts.
    address[13] public contracts;
    address[] public pendingContracts;
    VerusObjects.voteState public pendingVoteState;
    bytes32 public newContractsPendingHash;
    address contractOwner;

    uint8 constant TYPE_CONTRACT = 1;
    uint8 constant TYPE_REVOKE = 2;
    uint8 constant TYPE_RECOVER = 3;
    uint8 constant NUM_ADDRESSES_FOR_REVOKE = 2;
    uint8 constant PENDING = 1;
    uint8 constant COMPLETE = 2;
    uint8 constant UPGRADE_IN_PROCESS = 3;
    uint8 constant ERROR = 4;
    uint8 constant AMOUNT_OF_CONTRACTS = 13;
    uint8 constant REQUIREDAMOUNTOFVOTES = 100;
    uint8 constant WINNINGAMOUNT = 51;

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
        if (contractOwner != address(0)){

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
            notarizationSerializer = NotarizationSerializer(_newContractAddress[uint(VerusConstants.ContractType.NotarizationSerializer)]);
            
            verusBridgeStorage = VerusBridgeStorage(_newContractAddress[uint(VerusConstants.ContractType.VerusBridgeStorage)]);
            verusNotarizerStorage = VerusNotarizerStorage(_newContractAddress[uint(VerusConstants.ContractType.VerusNotarizerStorage)]);
            verusBridgeMaster = VerusBridgeMaster(_newContractAddress[uint(VerusConstants.ContractType.VerusBridgeMaster)]);

            verusBridgeStorage.setContracts(contracts); 
            verusNotarizerStorage.setContracts(contracts); 
            verusBridgeMaster.setContracts(contracts); 
            tokenManager.setContracts(_newContractAddress[uint(VerusConstants.ContractType.VerusSerializer)], 
                                     _newContractAddress[uint(VerusConstants.ContractType.VerusBridge)]);
        } 
       
        contractOwner = address(0);  //Blow the fuse i.e. make it one time only.
    }

    function upgradeContracts(VerusObjects.upgradeInfo memory _newContractPackage) public returns (uint8) {

        if (newContractsPendingHash != bytes32(0)) {
            return UPGRADE_IN_PROCESS;
        }

        checkValidContractUpgrade(_newContractPackage);
            
        return PENDING; 
    }

    function recoverString(bytes memory be, uint8 vs, bytes32 rs, bytes32 ss) public view returns (address)
    {
        bytes32 hashValue;

        VerusSerializer verusSerializer = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]);

        hashValue = sha256(abi.encodePacked(verusSerializer.writeCompactSize(be.length),be));
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

        return true;
    }

    function recover(VerusObjects.upgradeInfo memory _newContractPackage) public returns (uint8) {

        bytes memory be; 

        require(saltsUsed[_newContractPackage.salt] == false, "salt Already used");
        saltsUsed[_newContractPackage.salt] = true;
        
        require(_newContractPackage.contracts.length == NUM_ADDRESSES_FOR_REVOKE, "Input Identities wrong length");
        require(_newContractPackage.upgradeType == TYPE_RECOVER, "Wrong type of package");
        
        be = abi.encodePacked(be, _newContractPackage.contracts[0],_newContractPackage.contracts[1]);

        be = bytesToString(abi.encodePacked(be, uint8(_newContractPackage.upgradeType), _newContractPackage.salt));

        address signer = recoverString(be, _newContractPackage._vs, _newContractPackage._rs, _newContractPackage._ss);

        VerusObjects.notarizer memory notary;
        // get the notarys status from the mapping using its Notary i-address to check if it is valid.
        (notary.main, notary.recovery, notary.state) = verusNotarizer.notaryAddressMapping(_newContractPackage.notarizerID);

        if (signer != notary.recovery)
        {
            emit contractUpdated(false);
            return ERROR;  
        }
        verusNotarizer.updateNotarizer(_newContractPackage.notarizerID, _newContractPackage.contracts[0], 
                                       _newContractPackage.contracts[1], VerusConstants.NOTARY_VALID);

        return COMPLETE;
    }

    function checkValidContractUpgrade(VerusObjects.upgradeInfo memory _newContractPackage) private {

        bytes memory be; 

        require(saltsUsed[_newContractPackage.salt] == false, "salt Already used");
        saltsUsed[_newContractPackage.salt] = true;

        require(contracts.length == _newContractPackage.contracts.length, "Input contracts wrong length");
        
        // TODO: Check to see if a currency upgrade contract is in action, if so end.

        for (uint j = 0; j < contracts.length; j++)
        {
            be = abi.encodePacked(be, _newContractPackage.contracts[j]);
            pendingContracts.push(_newContractPackage.contracts[j]);
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

        newContractsPendingHash = keccak256(be);
         
    }

    function bytesToString (bytes memory input) private pure returns (bytes memory output)
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

    function runContractsUpgrade() public returns (uint8) {

        if (pendingContracts.length == AMOUNT_OF_CONTRACTS && 
            pendingVoteState.count == REQUIREDAMOUNTOFVOTES && 
            pendingVoteState.agree >= WINNINGAMOUNT ) {
            
            address[13] memory tempcontracts;

            for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++)
            {
                tempcontracts[i] = pendingContracts[i];
            }

            // only update contracts one at a time in a loop, in case of multiple contract updates in one upgrade.
            for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++)
            {       
                // if, else if instead of switch() case()
                if(i == uint(VerusConstants.ContractType.TokenManager) && tempcontracts[uint(VerusConstants.ContractType.TokenManager)] != address(tokenManager)) {
                    tokenManager = TokenManager(tempcontracts[uint(VerusConstants.ContractType.TokenManager)]);
                    verusBridge.setContracts(tempcontracts);
                    verusBridgeStorage.setContracts(tempcontracts);
                    verusInfo.setContracts(tempcontracts);
                    exportManager.setContract(tempcontracts[uint(VerusConstants.ContractType.TokenManager)]);
                    tokenManager.setContracts(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)], 
                                tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]); 
                }

                else if (i == uint(VerusConstants.ContractType.VerusSerializer) && tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)] != contracts[uint(VerusConstants.ContractType.VerusSerializer)])  {   
                    verusCrossChainExport.setContract(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)]);
                    tokenManager.setContracts(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)], 
                                            tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]);
                    verusBridge.setContracts(tempcontracts);  
                    verusProof.setContracts(tempcontracts);
                    verusNotarizer.setContracts(tempcontracts);
                    notarizationSerializer.setContract(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)]);
                }

                else if (i == uint(VerusConstants.ContractType.VerusProof) && tempcontracts[uint(VerusConstants.ContractType.VerusProof)] != address(verusProof)) {
                    verusProof = VerusProof(contracts[uint(VerusConstants.ContractType.VerusProof)]); 
                    verusBridge.setContracts(tempcontracts);             
                }

                else if (i == uint(VerusConstants.ContractType.VerusNotarizer) && tempcontracts[uint(VerusConstants.ContractType.VerusNotarizer)] != address(verusNotarizer)) {
                    verusNotarizer = VerusNotarizer(tempcontracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
                    verusBridgeMaster.setContracts(tempcontracts);
                    verusInfo.setContracts(tempcontracts);
                    verusNotarizerStorage.setContracts(tempcontracts);
                    verusProof.setContracts(tempcontracts);
                }

                else if (i == uint(VerusConstants.ContractType.VerusBridge) && tempcontracts[uint(VerusConstants.ContractType.VerusBridge)] != address(verusBridge)) {
                    verusBridge = VerusBridge(tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]);
                    verusBridgeMaster.setContracts(tempcontracts);
                    verusBridgeStorage.setContracts(tempcontracts);
                    verusNotarizerStorage.setContracts(tempcontracts);  
                    tokenManager.setContracts(tempcontracts[uint(VerusConstants.ContractType.VerusSerializer)], 
                                            tempcontracts[uint(VerusConstants.ContractType.VerusBridge)]); 
                }

                else if (i == uint(VerusConstants.ContractType.VerusInfo) && tempcontracts[uint(VerusConstants.ContractType.VerusInfo)] != address(verusInfo)) {
                    verusInfo = VerusInfo(tempcontracts[uint(VerusConstants.ContractType.VerusInfo)]);
                    verusBridgeMaster.setContracts(tempcontracts);
                }
                
                else if (i == uint(VerusConstants.ContractType.ExportManager) && tempcontracts[uint(VerusConstants.ContractType.ExportManager)] != address(exportManager))  {    
                    exportManager = ExportManager(tempcontracts[uint(VerusConstants.ContractType.ExportManager)]);
                    verusBridge.setContracts(tempcontracts);   
                }

                else if (i == uint(VerusConstants.ContractType.VerusBridgeMaster) && tempcontracts[uint(VerusConstants.ContractType.VerusBridgeMaster)] != contracts[uint(VerusConstants.ContractType.VerusBridgeMaster)])  {  
                    verusBridgeMaster.transferETH(tempcontracts[uint(VerusConstants.ContractType.VerusBridgeMaster)]);
                    verusBridgeMaster = VerusBridgeMaster(tempcontracts[uint(VerusConstants.ContractType.VerusBridgeMaster)]);
                    verusBridge.setContracts(tempcontracts);
                    verusNotarizer.setContracts(tempcontracts);
                    verusNotarizerStorage.setContracts(tempcontracts);  
                }

                else if (i == uint(VerusConstants.ContractType.NotarizationSerializer) && tempcontracts[uint(VerusConstants.ContractType.NotarizationSerializer)] != contracts[uint(VerusConstants.ContractType.NotarizationSerializer)])  {   
                    notarizationSerializer = NotarizationSerializer(tempcontracts[uint(VerusConstants.ContractType.NotarizationSerializer)]);
                    verusNotarizer.setContracts(tempcontracts);
                }

            }

            // Once all the contracts are set copy the new values to the global
            for (uint i = 0; i < uint(VerusConstants.ContractType.LastIndex); i++) 
            {
                contracts[i] = pendingContracts[i];
            }

            delete pendingContracts;
            delete pendingVoteState;
            newContractsPendingHash = bytes32(0);
            emit contractUpdated(true);
            return COMPLETE;

        }

        return ERROR;
    }

    function updateVote(bool voted) public {

        require(msg.sender == contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
        if (pendingVoteState.count < REQUIREDAMOUNTOFVOTES) {
            pendingVoteState.count++;
        
            if(voted) {
                pendingVoteState.agree++;
            }
        }
    }

    function getVoteState() public view returns (VerusObjects.voteState memory) {

        return pendingVoteState;

    }
    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) private pure returns (address) {

        return ecrecover(_h, _v, _r, _s);
    }

    function getBridgeAddress() public view returns (address)
    {
        return contracts[uint(VerusConstants.ContractType.VerusBridge)];
    }
}