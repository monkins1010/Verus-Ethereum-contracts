// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;


import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VerusNotarizerStorage {

    address upgradeContract;
    address verusBridge;
    address verusNotarizer;
    address verusBridgeMaster;
    using SafeMath for uint;

    mapping (address => uint32) public poolAvailable;
    mapping (bytes32 => bytes32) public storageGlobal;
    mapping (bytes32 => bytes) private proofs;
    mapping (bytes32 => uint256) public claimableFees;
    
    constructor(address upgradeContractAddress)
    {
        upgradeContract = upgradeContractAddress; 
    }

    function setContracts(address[13] memory contracts) public {
        
        require (msg.sender == upgradeContract);
        verusBridge = contracts[uint(VerusConstants.ContractType.VerusBridge)];
        verusNotarizer = contracts[uint(VerusConstants.ContractType.VerusNotarizer)];
        verusBridgeMaster = contracts[uint(VerusConstants.ContractType.VerusBridgeMaster)]; 

    }

    function setPoolAvailable() public {

        require (msg.sender == verusNotarizer,"setpool:callfromNotarizeronly");
        poolAvailable[VerusConstants.VerusBridgeAddress] = uint32(block.number); 

    }

    // Generic Storage global for future Expansion
    function pushStorageGlobal(bytes32 key, bytes32 data) public {

        require (msg.sender == address(verusBridge));
        storageGlobal[key] = data;

    }

    function pushNewProof(bytes memory data, uint32 height) public {

        require (msg.sender == verusNotarizer,"pushNotarizedProof:callfromNotarizeronly");
        proofs[bytes32(uint256(height))] = data;

    }

    function getProof(bytes32 key) public view returns (bytes memory) {

        require (msg.sender == verusNotarizer,"getProof:callfromNotarizeronly");

        return proofs[key];

    }

    function setClaimableFees(bytes32 claiment, uint256 fee) public {

        require (msg.sender == verusBridgeMaster);
        claimableFees[claiment] = fee;
    }
    
    function appendClaimableFees(bytes32 claiment, uint256 fee) public returns (uint256) {

        require (msg.sender == verusBridgeMaster);
        claimableFees[claiment] += fee;
        return claimableFees[claiment];
    }

}