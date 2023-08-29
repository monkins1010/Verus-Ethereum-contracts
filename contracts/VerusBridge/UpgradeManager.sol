// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../Storage/StorageMaster.sol";

contract UpgradeManager is VerusStorage {

    uint8 constant TYPE_CONTRACT = 1;
    uint8 constant TYPE_REVOKE = 2;
    uint8 constant TYPE_RECOVER = 3;
    uint8 constant TYPE_AUTO_REVOKE = 4;
    uint8 constant NUM_ADDRESSES_FOR_REVOKE = 2;
    uint8 constant PENDING = 1;
    uint8 constant COMPLETE = 2;
    uint8 constant UPGRADE_IN_PROCESS = 3;
    uint8 constant ERROR = 4;
    uint8 constant REQUIREDAMOUNTOFVOTES = 100;
    uint8 constant WINNINGAMOUNT = 51;

    event contractUpdated(bool);
    address internal contractOwner;


    function upgradeContracts(bytes calldata data) external payable returns (uint8) {


        require(msg.value > VerusConstants.upgradeFee);

        setNotaryFees(msg.value / VerusConstants.SATS_TO_WEI_STD);

        VerusObjects.upgradeInfo memory _newContractPackage;

        (_newContractPackage) = abi.decode(data, (VerusObjects.upgradeInfo));
        
        checkValidContractUpgrade(_newContractPackage);
            
        return PENDING; 
    }

    function setNotaryFees(uint256 notaryFees) private {  //sent in as SATS
      
        uint256 numOfNotaries = notaries.length;
        uint64 notariesShare = uint64(notaryFees / numOfNotaries);
        for (uint i=0; i < numOfNotaries; i++)
        {
            uint176 notary;
            notary = uint176(uint160(notaryAddressMapping[notaries[i]].main));
            notary |= (uint176(0x0c14) << VerusConstants.UINT160_BITS_SIZE); //set at type eth
            claimableFees[bytes32(uint256(notary))] += notariesShare;
        }
    }

    function recoverString(bytes memory be, uint8 vs, bytes32 rs, bytes32 ss) private pure returns (address)
    {
        bytes32 hashValue;

        hashValue = sha256(abi.encodePacked(writeCompactSize(be.length),be));
        hashValue = sha256(abi.encodePacked(uint8(19),hex"5665727573207369676e656420646174613a0a", hashValue)); // prefix = 19(len) + "Verus signed data:\n"

        return recoverSigner(hashValue, vs - 4, rs, ss);

    }

    function checkValidContractUpgrade(VerusObjects.upgradeInfo memory _newContractPackage) private {

        bytes memory be; 
        address contractsHash;

        require(saltsUsed[_newContractPackage.salt] == false, "salt Already used");
        saltsUsed[_newContractPackage.salt] = true;

        require(contracts.length == _newContractPackage.contracts.length, "Input contracts wrong length");
        
        for (uint i = 0; i < contracts.length; i++)
        {
            be = abi.encodePacked(be, _newContractPackage.contracts[i]);
        }

        be = abi.encodePacked(be, uint8(_newContractPackage.upgradeType), _newContractPackage.salt);

        contractsHash = address(uint160(uint256(keccak256(be))));

        if (checkContractsCanUpgrade(contractsHash)) {

            for (uint j = 0; j < uint(VerusConstants.NUMBER_OF_CONTRACTS); j++)
            {       
                if (contracts[j] != _newContractPackage.contracts[j]) {
                    contracts[j] = _newContractPackage.contracts[j];
                    //NOTE: Upgraded contracts need a initialize() function to be present, so they can initialize
                    (bool success,) = _newContractPackage.contracts[j].delegatecall(abi.encodeWithSignature("initialize()"));
                    require(success);
                }
            }
        }
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

    function checkContractsCanUpgrade(address contractsHash) private view  returns (bool) {

        uint8 countOfAgreedVotes;
        
        for(uint i = 0; i < rollingUpgradeVotes.length; i++) 
        {
            if (contractsHash == rollingUpgradeVotes[i])
                countOfAgreedVotes++;
        }

        return countOfAgreedVotes > 50;
   
    }

    function recoverSigner(bytes32 _h, uint8 _v, bytes32 _r, bytes32 _s) private pure returns (address) {

        return ecrecover(_h, _v, _r, _s);
    }

    function writeCompactSize(uint newNumber) public pure returns(bytes memory) {
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