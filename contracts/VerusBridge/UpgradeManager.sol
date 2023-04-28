// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../Storage/StorageMaster.sol";

contract UpgradeManager is VerusStorage {

    uint8 constant TYPE_CONTRACT = 1;
    uint8 constant TYPE_REVOKE = 2;
    uint8 constant TYPE_RECOVER = 3;
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
        
        VerusObjects.upgradeInfo memory _newContractPackage;

        (_newContractPackage) = abi.decode(data, (VerusObjects.upgradeInfo));
        
        
        if (newContractsPendingHash != bytes32(0)) {
            return UPGRADE_IN_PROCESS;
        }

        checkValidContractUpgrade(_newContractPackage);
            
        return PENDING; 
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
        notary = notaryAddressMapping[_newContractPackage.notarizerID];

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

        if (pendingContracts.length == VerusConstants.AMOUNT_OF_CONTRACTS && 
            pendingVoteState.count == REQUIREDAMOUNTOFVOTES && 
            pendingVoteState.agree >= WINNINGAMOUNT ) {
            
            for (uint i = 0; i < uint(VerusConstants.AMOUNT_OF_CONTRACTS); i++)
            {       
                    if(contracts[i] != pendingContracts[i]) {
                        contracts[i] = pendingContracts[i];
                    }
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

    function setSaltsUsed(bytes32 salt) public {
        require(msg.sender == contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
        saltsUsed[salt] = true;

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