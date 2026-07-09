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
    uint8 constant TYPE_HALT = 5;
    uint8 constant TYPE_RESUME = 6;
    uint8 constant NUM_ADDRESSES_FOR_REVOKE = 2;
    uint8 constant COMPLETE = 2;
    uint8 constant ERROR = 4;

    using VerusBlake2b for bytes;

    //reset to empty 9-July-26
    function initialize() external {}
    
    function updateNotarizer(address notarizer, address mainAddress, address revokeAddress, uint8 state) private
    {
        notaryAddressMapping[notarizer] = VerusObjects.notarizer(mainAddress, revokeAddress, state);
    }

    // Auto-halts submitImports when > 3 notaries are revoked; auto-clears only if the flag was
    // set by this function (exact HALT_SUBMIT_IMPORTS value) and fewer than 4 remain revoked.
    function _checkAutoHalt() private {
        uint revokedCount;
        for (uint i = 0; i < notaries.length; i++) {
            if (notaryAddressMapping[notaries[i]].state == VerusConstants.NOTARY_REVOKED) {
                revokedCount++;
            }
        }
        if (revokedCount > 3) {
            if (claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] == 0) {
                claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] = VerusConstants.HALT_SUBMIT_IMPORTS;
            }
        } else if (claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] == VerusConstants.HALT_SUBMIT_IMPORTS) {
            delete claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY];
        }
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
                _checkAutoHalt();
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
        
        be = bytesToString(abi.encodePacked(uint8(TYPE_RECOVER), _newRecoveryInfo.contracts[0], _newRecoveryInfo.contracts[1], _newRecoveryInfo.salt));

        address signer = recoverString(be, _newRecoveryInfo._vs, _newRecoveryInfo._rs, _newRecoveryInfo._ss);

        if (signer != notaryAddressMapping[_newRecoveryInfo.notarizerID].recovery)
        {
            revert();  
        }
                 
        updateNotarizer(_newRecoveryInfo.notarizerID, _newRecoveryInfo.contracts[0], 
                                       _newRecoveryInfo.contracts[1], VerusConstants.NOTARY_VALID);
        _checkAutoHalt();
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
        _checkAutoHalt();
        return COMPLETE;
    }

    /// @notice Halt or resume bridge functions with 3 notary signatures bearing fresh one-time salts.
    /// @param dataIn abi.encode(revokeRecoverInfo[] memory sigs, uint8 flags)
    ///   flags: 0 = normal, 1 = halt notarizations, 2 = halt submitimports, 4 = halt sendtransfers (combinable)
    function haltBridge(bytes calldata dataIn) public {

        (VerusObjects.revokeRecoverInfo[] memory _haltPacket, uint8 flags) = abi.decode(dataIn, (VerusObjects.revokeRecoverInfo[], uint8));
        bytes memory be;
        uint counter;

        for (uint i = 0; i < _haltPacket.length; i++) {

            for (uint j = i + 1; j < _haltPacket.length; j++) {
                if (_haltPacket[i].notarizerID == _haltPacket[j].notarizerID) {
                    revert("Duplicate signatures");
                }
            }

            require(saltsUsed[_haltPacket[i].salt] == false, "salt already used");
            saltsUsed[_haltPacket[i].salt] = true;

            be = bytesToString(abi.encodePacked(uint8(TYPE_HALT), flags, _haltPacket[i].salt));
            address signer = recoverString(be, _haltPacket[i]._vs, _haltPacket[i]._rs, _haltPacket[i]._ss);

            if (signer == notaryAddressMapping[_haltPacket[i].notarizerID].main &&
                notaryAddressMapping[_haltPacket[i].notarizerID].state == VerusConstants.NOTARY_VALID) {
                counter++;
            }
        }

        require(counter >= 3, "Need 3 valid notary signatures");

        claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] = flags;
    }

    /// @notice Re-enable all bridge functions — requires 8 valid notary signatures with fresh one-time salts.
    /// @param dataIn abi.encode(revokeRecoverInfo[] memory sigs)  — must contain >= 8 unique valid notaries
    function resumeBridge(bytes calldata dataIn) public {

        VerusObjects.revokeRecoverInfo[] memory _resumePacket = abi.decode(dataIn, (VerusObjects.revokeRecoverInfo[]));
        bytes memory be;
        uint counter;

        for (uint i = 0; i < _resumePacket.length; i++) {

            for (uint j = i + 1; j < _resumePacket.length; j++) {
                if (_resumePacket[i].notarizerID == _resumePacket[j].notarizerID) {
                    revert("Duplicate signatures");
                }
            }

            require(saltsUsed[_resumePacket[i].salt] == false, "salt already used");
            saltsUsed[_resumePacket[i].salt] = true;

            be = bytesToString(abi.encodePacked(uint8(TYPE_RESUME), _resumePacket[i].salt));
            address signer = recoverString(be, _resumePacket[i]._vs, _resumePacket[i]._rs, _resumePacket[i]._ss);

            if (signer == notaryAddressMapping[_resumePacket[i].notarizerID].main &&
                notaryAddressMapping[_resumePacket[i].notarizerID].state == VerusConstants.NOTARY_VALID) {
                counter++;
            }
        }

        require(counter >= 8, "Need 8 valid notary signatures");

        delete claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY];
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
