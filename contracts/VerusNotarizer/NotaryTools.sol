// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.22 <0.9.0;
pragma abicoder v2;

import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusSerializer.sol";
import "./NotarizationSerializer.sol";
import "../MMR/VerusBlake2b.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Storage/StorageMaster.sol";
import "../VerusBridge/Token.sol";

contract NotaryTools is VerusStorage {
        
    uint8 constant FLAG_FRACTIONAL = 1;
    uint8 constant FLAG_REFUNDING = 4;
    uint8 constant FLAG_LAUNCHCONFIRMED = 0x10;
    uint8 constant FLAG_LAUNCHCOMPLETEMARKER = 0x20;
    uint8 constant OFFSET_FOR_HEIGHT = 224;
    uint8 constant TYPE_REVOKE = 2;
    uint8 constant TYPE_RECOVER = 3;
    uint8 constant NUM_ADDRESSES_FOR_REVOKE = 2;
    uint8 constant COMPLETE = 2;
    uint8 constant ERROR = 4;

    using VerusBlake2b for bytes;
    
    function updateNotarizer(address notarizer, address mainAddress, address revokeAddress, uint8 state) private
    {
        notaryAddressMapping[notarizer] = VerusObjects.notarizer(mainAddress, revokeAddress, state);
    }


    function getProof(uint256 height) public view returns (bytes memory) {

        VerusObjectsNotarization.NotarizationForks[] memory latestForks;

        latestForks = decodeNotarization(0);

        require(height < uint256(latestForks[0].proposerPacked >> OFFSET_FOR_HEIGHT), "Latest proofs require paid service");

        return proofs[bytes32(height)];
    }

    function decodeNotarization(uint256 index) public view returns (VerusObjectsNotarization.NotarizationForks[] memory)
    {
        uint32 nextOffset;

        bytes storage tempArray = bestForks[index];

        bytes32 hashOfNotarization;
        bytes32 txid;
        bytes32 stateRoot;
        bytes32 packedPositions;
        bytes32 slotHash;
        VerusObjectsNotarization.NotarizationForks[] memory retval = new VerusObjectsNotarization.NotarizationForks[]((tempArray.length / 128) + 1);
        if (tempArray.length > 1)
        {
            bytes32 slot;
            assembly {
                        mstore(add(slot, 32),tempArray.slot)
                        slotHash := keccak256(add(slot, 32), 32)
                        }

            for (int i = 0; i < int(tempArray.length / 128); i++) 
            {
                assembly {
                    hashOfNotarization := sload(add(slotHash,nextOffset))
                    nextOffset := add(nextOffset, 1)  
                    txid := sload(add(slotHash,nextOffset))
                    nextOffset := add(nextOffset, 1) 
                    stateRoot := sload(add(slotHash,nextOffset))
                    nextOffset := add(nextOffset, 1) 
                    packedPositions :=sload(add(slotHash,nextOffset))
                    nextOffset := add(nextOffset, 1)
                }

                retval[uint(i)] =  VerusObjectsNotarization.NotarizationForks(hashOfNotarization, txid, stateRoot, packedPositions);
            }
        }
        return retval;
    }

     function recoverString(bytes memory be, uint8 vs, bytes32 rs, bytes32 ss) public pure returns (address)
    {
        bytes32 hashValue;

        hashValue = sha256(abi.encodePacked(writeCompactSize(be.length),be));
        hashValue = sha256(abi.encodePacked(uint8(19),hex"5665727573207369676e656420646174613a0a", hashValue)); //TODO: move to constants prefix = 19(len) + "Verus signed data:\n"

        return ecrecover(hashValue, vs - 4, rs, ss);

    }

    function revokeWithMainAddress(bytes calldata dataIn) public returns (bool) {

        VerusObjects.revokeInfo memory _revokePacket = abi.decode(dataIn, (VerusObjects.revokeInfo));
        
        bytes memory be; 

        require(saltsUsed[_revokePacket.salt] == false, "salt Already used");
        saltsUsed[_revokePacket.salt] = true;

        be = bytesToString(abi.encodePacked(uint8(TYPE_REVOKE), _revokePacket.salt));

        address signer = recoverString(be, _revokePacket._vs, _revokePacket._rs, _revokePacket._ss);

        if (notaryAddressMapping[_revokePacket.notaryID].main != signer || notaryAddressMapping[_revokePacket.notaryID].state == VerusConstants.NOTARY_REVOKED)
        {
            return false;  
        }

        updateNotarizer(_revokePacket.notaryID, address(0), notaryAddressMapping[_revokePacket.notaryID].recovery, VerusConstants.NOTARY_REVOKED);

        return true;
    }

    function revokeWithMultiSig(bytes calldata dataIn) public returns (bool) {

        // Revoke with a quorum of notary sigs.
        (VerusObjects.revokeRecoverInfo[] memory _revokePacket, address notarizerBeingRevoked) = abi.decode(dataIn, (VerusObjects.revokeRecoverInfo[], address));
        bytes memory be; 

        require(_revokePacket.length >= ((notaries.length >> 1) + 1), "not enough sigs");

        for (uint i = 0; i < _revokePacket.length; i++) {

            for (uint j = i + 1; j < _revokePacket.length; j++) { 
                if (_revokePacket[i].notarizerID == _revokePacket[j].notarizerID) {
                    revert("Duplicate signatures");
                }
            }

            require(saltsUsed[_revokePacket[i].salt] == false, "salt Already used");
            saltsUsed[_revokePacket[i].salt] = true;

            be = bytesToString(abi.encodePacked(uint8(TYPE_REVOKE),notarizerBeingRevoked, _revokePacket[i].salt));
            address signer = recoverString(be, _revokePacket[i]._vs, _revokePacket[i]._rs, _revokePacket[i]._ss);

            if (signer != _revokePacket[i].notarizerID || notaryAddressMapping[_revokePacket[i].notarizerID].state != VerusConstants.NOTARY_VALID) {
                    revert("Notary not Valid");
            }
        }

        updateNotarizer(notarizerBeingRevoked, address(0), notaryAddressMapping[notarizerBeingRevoked].recovery, VerusConstants.NOTARY_REVOKED);

        return true;
    }

    function recoverWithRecoveryAddress(bytes calldata dataIn) public returns (uint8) {

        VerusObjects.upgradeInfo memory _newRecoveryInfo = abi.decode(dataIn, (VerusObjects.upgradeInfo));
  
        bytes memory be; 

        require(saltsUsed[_newRecoveryInfo.salt] == false, "salt Already used");
        saltsUsed[_newRecoveryInfo.salt] = true;
        
        require(_newRecoveryInfo.contracts.length == NUM_ADDRESSES_FOR_REVOKE, "Input Identities wrong length");
        require(_newRecoveryInfo.upgradeType == TYPE_RECOVER, "Wrong type of package");
        
        be = bytesToString(abi.encodePacked(_newRecoveryInfo.contracts[0],_newRecoveryInfo.contracts[1], uint8(_newRecoveryInfo.upgradeType), _newRecoveryInfo.salt));

        address signer = recoverString(be, _newRecoveryInfo._vs, _newRecoveryInfo._rs, _newRecoveryInfo._ss);

        if (signer != notaryAddressMapping[_newRecoveryInfo.notarizerID].recovery)
        {
            return ERROR;  
        }
        updateNotarizer(_newRecoveryInfo.notarizerID, _newRecoveryInfo.contracts[0], 
                                       _newRecoveryInfo.contracts[1], VerusConstants.NOTARY_VALID);

        return COMPLETE;
    }

    function recoverWithMultiSig(bytes calldata dataIn) public returns (uint8) {
        
        // Recover with a quorum of notary sigs.
        (VerusObjects.revokeRecoverInfo[] memory _recoverPacket, address notarizerBeingRecovered, address newMainAddr, address newRevokeAddr) = abi.decode(dataIn, (VerusObjects.revokeRecoverInfo[], address, address, address));
        bytes memory be; 

        require(_recoverPacket.length >= ((notaries.length >> 1) + 1), "not enough sigs");
        require(notaryAddressMapping[notarizerBeingRecovered].state == VerusConstants.NOTARY_VALID, "Notary not revoked");

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

            if (signer != _recoverPacket[i].notarizerID || notaryAddressMapping[_recoverPacket[i].notarizerID].state != VerusConstants.NOTARY_VALID) {
                    revert("Notary not Valid");
            }
        }

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

}
