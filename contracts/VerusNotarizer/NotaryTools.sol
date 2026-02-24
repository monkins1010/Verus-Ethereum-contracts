// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusSerializer.sol";
import "./NotarizationSerializer.sol";
import "../MMR/VerusBlake2b.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Storage/StorageMaster.sol";
import "../VerusBridge/Token.sol";
import "../VerusBridge/TokenManager.sol";

contract NotaryTools is VerusStorage {
        

    uint8 constant TYPE_REVOKE = 2;
    uint8 constant TYPE_RECOVER = 3;
    uint8 constant TYPE_AUTO_REVOKE = 4;
    uint8 constant NUM_ADDRESSES_FOR_REVOKE = 2;
    uint8 constant COMPLETE = 2;
    uint8 constant ERROR = 4;

    using VerusBlake2b for bytes;
    
    function updateNotarizer(address notarizer, address mainAddress, address revokeAddress, uint8 state) private
    {
        notaryAddressMapping[notarizer] = VerusObjects.notarizer(mainAddress, revokeAddress, state);
    }

    function recoverString(bytes memory be, uint8 vs, bytes32 rs, bytes32 ss) public pure returns (address)
    {
        bytes32 hashValue;

        hashValue = sha256(abi.encodePacked(writeCompactSize(be.length),be));
        hashValue = sha256(abi.encodePacked(uint8(19),hex"5665727573207369676e656420646174613a0a", hashValue)); //TODO: move to constants prefix = 19(len) + "Verus signed data:\n"

        return ecrecover(hashValue, vs - 4, rs, ss);
    }

    function revokeWithMainAddress(bytes calldata) public returns (bool) {
          
        for (uint i; i<notaries.length; i++) {
            if(msg.sender == notaryAddressMapping[notaries[i]].main) {
                require(notaryAddressMapping[notaries[i]].state == VerusConstants.NOTARY_VALID, "Notary not Valid");
                notaryAddressMapping[notaries[i]].state = VerusConstants.NOTARY_REVOKED;
                return true;
            }
        }
        revert("Notary not found");
    }

    function revokeWithMultiSig(bytes calldata dataIn) public returns (bool) {

        // Revoke with a quorum of notary sigs.
        (VerusObjects.revokeRecoverInfo[] memory _revokePacket, address notarizerBeingRevoked) = abi.decode(dataIn, (VerusObjects.revokeRecoverInfo[], address));
        bytes memory be; 

        uint counter;
        for (uint i = 0; i < _revokePacket.length; i++) {

            for (uint j = i + 1; j < _revokePacket.length; j++) { 
                if (_revokePacket[i].notarizerID == _revokePacket[j].notarizerID) {
                    revert("Duplicate signatures");
                }
            }

            require(saltsUsed[_revokePacket[i].salt] == false, "salt already used");
            saltsUsed[_revokePacket[i].salt] = true;

            be = bytesToString(abi.encodePacked(uint8(TYPE_REVOKE),notarizerBeingRevoked, _revokePacket[i].salt));
            address signer = recoverString(be, _revokePacket[i]._vs, _revokePacket[i]._rs, _revokePacket[i]._ss);

            if (signer == notaryAddressMapping[_revokePacket[i].notarizerID].main && 
                notaryAddressMapping[_revokePacket[i].notarizerID].state == VerusConstants.NOTARY_VALID) {
                    counter++;
            }
        }
        require(counter >= ((notaries.length >> 1) + 1), "not enough signatures");

        notaryAddressMapping[notarizerBeingRevoked].state = VerusConstants.NOTARY_REVOKED;

        return true;
    }

    function recoverWithRecoveryAddress(bytes calldata dataIn) public returns (uint8) {

        VerusObjects.upgradeInfo memory _newRecoveryInfo = abi.decode(dataIn, (VerusObjects.upgradeInfo));
  
        bytes memory be; 

        require(saltsUsed[_newRecoveryInfo.salt] == false, "salt Already used");
        saltsUsed[_newRecoveryInfo.salt] = true;
        
        require(_newRecoveryInfo.contracts.length == NUM_ADDRESSES_FOR_REVOKE, "Input Identities wrong length");
        require(_newRecoveryInfo.upgradeType == TYPE_RECOVER, "Wrong type of package");
        require(notaryAddressMapping[_newRecoveryInfo.notarizerID].state == VerusConstants.NOTARY_REVOKED, "Notary not revoked");
        
        be = bytesToString(abi.encodePacked(_newRecoveryInfo.contracts[0],_newRecoveryInfo.contracts[1], uint8(_newRecoveryInfo.upgradeType), _newRecoveryInfo.salt));

        address signer = recoverString(be, _newRecoveryInfo._vs, _newRecoveryInfo._rs, _newRecoveryInfo._ss);

        if (signer != notaryAddressMapping[_newRecoveryInfo.notarizerID].recovery)
        {
            revert();  
        }
                 
        updateNotarizer(_newRecoveryInfo.notarizerID, _newRecoveryInfo.contracts[0], 
                                       _newRecoveryInfo.contracts[1], VerusConstants.NOTARY_VALID);
        return COMPLETE;
    }

    function recoverWithMultiSig(bytes calldata dataIn) public returns (uint8) {
        
        // Recover with a quorum of notary sigs.
        (VerusObjects.revokeRecoverInfo[] memory _recoverPacket, address notarizerBeingRecovered, address newMainAddr, address newRevokeAddr) = abi.decode(dataIn, (VerusObjects.revokeRecoverInfo[], address, address, address));
        bytes memory be; 

        require(notaryAddressMapping[notarizerBeingRecovered].state == VerusConstants.NOTARY_REVOKED, "Notary not revoked");
        
        uint counter;
        for (uint i = 0; i < _recoverPacket.length; i++) {

            for (uint j = i + 1; j < _recoverPacket.length; j++) { 
                if (_recoverPacket[i].notarizerID == _recoverPacket[j].notarizerID) {
                    revert("Duplicate signatures");
                }
            }

            require(saltsUsed[_recoverPacket[i].salt] == false, "salt Already used");
            saltsUsed[_recoverPacket[i].salt] = true;

            be = bytesToString(abi.encodePacked(uint8(TYPE_RECOVER),notarizerBeingRecovered, newMainAddr, newRevokeAddr, _recoverPacket[i].salt));
            address signer = recoverString(be, _recoverPacket[i]._vs, _recoverPacket[i]._rs, _recoverPacket[i]._ss);

            if (signer == notaryAddressMapping[_recoverPacket[i].notarizerID].recovery &&
                notaryAddressMapping[_recoverPacket[i].notarizerID].state == VerusConstants.NOTARY_VALID) {
                counter++;
            }
        }
        require(counter >= ((notaries.length >> 1) + 1), "not enough sigs");

        updateNotarizer(notarizerBeingRecovered, newMainAddr, newRevokeAddr, VerusConstants.NOTARY_VALID);

        return COMPLETE;
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


    function writeCompactSize(uint newNumber) internal pure returns(bytes memory) {
        bytes memory output;
        if (newNumber < uint8(253))
        {   
            output = abi.encodePacked(uint8(newNumber));
        }
        else if (newNumber <= 0xFFFF)
        {   
            output = abi.encodePacked(uint8(253),uint8(newNumber & 0xff),uint8(newNumber >> 8));
        }
        else if (newNumber <= 0xFFFFFFFF)
        {   
            output = abi.encodePacked(uint8(254),uint8(newNumber & 0xff),uint8(newNumber >> 8),uint8(newNumber >> 16),uint8(newNumber >> 24));
        }
        else 
        {   
            output = abi.encodePacked(uint8(254),uint8(newNumber & 0xff),uint8(newNumber >> 8),uint8(newNumber >> 16),uint8(newNumber >> 24),uint8(newNumber >> 32),uint8(newNumber >> 40),uint8(newNumber >> 48),uint8(newNumber >> 56));
        }
        return output;
    }

    function launchContractTokens(bytes calldata data) external {

        VerusObjects.setupToken[] memory tokensToDeploy = abi.decode(data, (VerusObjects.setupToken[]));

        for (uint256 i = 0; i < tokensToDeploy.length; i++) {

            (bool success,) = contracts[uint160(VerusConstants.ContractType.TokenManager)].delegatecall(abi.encodeWithSelector(TokenManager.recordToken.selector,
                tokensToDeploy[i].iaddress,
                tokensToDeploy[i].erc20ContractAddress,
                tokensToDeploy[i].name,
                tokensToDeploy[i].ticker,
                tokensToDeploy[i].flags,
                uint256(0)
            ));
            
            require(success);
        }
    }

}
