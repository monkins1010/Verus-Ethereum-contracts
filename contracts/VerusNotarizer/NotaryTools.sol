// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
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

    function getNotaryETHAddress(uint256 number) public view returns (address)
    {
        return notaryAddressMapping[notaries[number]].main;
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

    function revoke(bytes calldata dataIn) public returns (bool) {

        //TODO: Revoke if keys compromized, or revoke if lost main key but have recovery and a majority of sigs from notaries
        //TODO: if majority of Notaries are revoked then stop Exports.
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

    function recover(bytes calldata dataIn) public returns (uint8) {
       //TODO: recover with recovery or a majority of sigs from notaries recovery addresses
        VerusObjects.upgradeInfo memory _newContractPackage = abi.decode(dataIn, (VerusObjects.upgradeInfo));
  
        bytes memory be; 

        require(saltsUsed[_newContractPackage.salt] == false, "salt Already used");
        saltsUsed[_newContractPackage.salt] = true;
        
        require(_newContractPackage.contracts.length == NUM_ADDRESSES_FOR_REVOKE, "Input Identities wrong length");
        require(_newContractPackage.upgradeType == TYPE_RECOVER, "Wrong type of package");
        
        be = bytesToString(abi.encodePacked(_newContractPackage.contracts[0],_newContractPackage.contracts[1], uint8(_newContractPackage.upgradeType), _newContractPackage.salt));

        address signer = recoverString(be, _newContractPackage._vs, _newContractPackage._rs, _newContractPackage._ss);

        if (signer != notaryAddressMapping[_newContractPackage.notarizerID].recovery)
        {
            return ERROR;  
        }
        updateNotarizer(_newContractPackage.notarizerID, _newContractPackage.contracts[0], 
                                       _newContractPackage.contracts[1], VerusConstants.NOTARY_VALID);

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

    function launchContractTokens(bytes calldata data) external {

        VerusObjects.setupToken[] memory tokensToDeploy = abi.decode(data, (VerusObjects.setupToken[]));

        for (uint256 i = 0; i < tokensToDeploy.length; i++) {

            recordToken(
                tokensToDeploy[i].iaddress,
                tokensToDeploy[i].erc20ContractAddress,
                tokensToDeploy[i].name,
                tokensToDeploy[i].ticker,
                tokensToDeploy[i].flags,
                uint256(0)
            );
        }
    }

    function recordToken(
        address _iaddress,
        address ethContractAddress,
        string memory name,
        string memory ticker,
        uint8 flags,
        uint256 tokenID
    ) private {

        address ERCContract;

        if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) 
        {
            if (flags & VerusConstants.TOKEN_LAUNCH == VerusConstants.TOKEN_LAUNCH) 
            {
                Token t = new Token(name, ticker); 
                ERCContract = address(t); 
            }
            else if (flags & VerusConstants.TOKEN_ETH_NFT_DEFINITION == VerusConstants.TOKEN_ETH_NFT_DEFINITION)
            {
                ERCContract = verusToERC20mapping[VerusConstants.VerusNFTID].erc20ContractAddress;
                tokenID = uint256(uint160(_iaddress)); //tokenID is the i address
            }
        }
        else 
        {
            ERCContract = ethContractAddress;
        }

        tokenList.push(_iaddress);
        verusToERC20mapping[_iaddress] = VerusObjects.mappedToken(ERCContract, flags, tokenList.length, name, tokenID);
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
