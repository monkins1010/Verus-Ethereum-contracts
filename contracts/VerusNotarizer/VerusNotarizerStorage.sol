// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;


import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusBridgeMaster.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VerusNotarizerStorage {

    address upgradeContract;
    address verusBridge;
    address verusNotarizer;
    using SafeMath for uint;

    bytes[] public PBaaSNotarization;
    mapping (address => uint32) public poolAvailable;
    mapping (address => uint256) public storageGlobal;
    
    constructor(address upgradeContractAddress)
    {
        upgradeContract = upgradeContractAddress; 
    }

    function setContracts(address[13] memory contracts) public {
        
        require(msg.sender == upgradeContract);
        verusBridge = contracts[uint(VerusConstants.ContractType.VerusBridge)];
        verusNotarizer = contracts[uint(VerusConstants.ContractType.VerusNotarizer)];

    }

    function setPoolAvailable() public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        poolAvailable[VerusConstants.VerusBridgeAddress] = uint32(block.number); 

    }

    function pushStorageGlobal(address iaddress,uint256 data) public {

        require(msg.sender == address(verusBridge));

        storageGlobal[iaddress] = data;

    }

    function setNotarization(bytes memory _notarization) public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
     
        PBaaSNotarization.push(_notarization); 

    }

    function resetNotarization(bytes calldata newCandidate, uint newconfirmed) public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");

        bytes memory confirmed = PBaaSNotarization[newconfirmed];
        delete PBaaSNotarization; 

        PBaaSNotarization.push(confirmed);
        PBaaSNotarization.push(newCandidate);

    }

    function nextNotarizationIndex() public view returns (uint){

        return PBaaSNotarization.length; 

    }

    function getLastStateRoot(uint position) public view returns (bytes32) {

        bytes storage tempNotarization;
        bytes32 stateRoot;
        bytes32 slotHash;

        tempNotarization = PBaaSNotarization[0];

        if (tempNotarization.length > 0)
        {
            assembly {
                slotHash := keccak256(add(tempNotarization.slot, 32), 32)
                stateRoot := sload(add(slotHash, position))
            }
        }
        return stateRoot;
    }
}