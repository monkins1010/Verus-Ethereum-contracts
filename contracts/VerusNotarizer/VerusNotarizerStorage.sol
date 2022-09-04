// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;


import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusBridgeMaster.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract VerusNotarizerStorage {

    address upgradeContract;
    address verusBridge;
    address verusNotarizer;
    using SafeMath for uint;

    mapping (bytes32 => VerusObjectsNotarization.CPBaaSNotarization) public PBaaSNotarization;
    mapping (address => uint32) public poolAvailable;
  
    VerusObjectsNotarization.NotarizationForks[] public bestForks;
    bytes32 public lastNotarizationTxid;
    mapping (address => uint256) public storageGlobal;
    
    constructor(address upgradeContractAddress)
    {
        upgradeContract = upgradeContractAddress; 
    }

    function setContracts(address[12] memory contracts) public {
        
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

    function getNotarization(bytes32 txid) public view returns (VerusObjectsNotarization.CPBaaSNotarization memory){

        return PBaaSNotarization[txid];

    }

    function setNotarization(VerusObjectsNotarization.CPBaaSNotarization memory _notarization) public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        
        // copying from memory to storage cannot be done directly
        bytes32 txidOfNotarization = _notarization.txid.hash;

        PBaaSNotarization[txidOfNotarization].version = _notarization.version; 
        PBaaSNotarization[txidOfNotarization].flags = _notarization.flags;
        PBaaSNotarization[txidOfNotarization].proposer = _notarization.proposer;
        PBaaSNotarization[txidOfNotarization].currencyid = _notarization.currencyid;
        PBaaSNotarization[txidOfNotarization].currencystate = _notarization.currencystate;
        PBaaSNotarization[txidOfNotarization].notarizationheight = _notarization.notarizationheight;
        PBaaSNotarization[txidOfNotarization].prevnotarization = _notarization.prevnotarization;
        PBaaSNotarization[txidOfNotarization].hashprevnotarization = _notarization.hashprevnotarization;
        PBaaSNotarization[txidOfNotarization].prevheight = _notarization.prevheight;
        PBaaSNotarization[txidOfNotarization].txid = _notarization.txid;

        for (uint i = 0; i < _notarization.currencystates.length; i++) {
 
            PBaaSNotarization[txidOfNotarization].currencystates.push(_notarization.currencystates[i]);
        }  
              
        for (uint i = 0; i < _notarization.proofroots.length; i++) {
 
            PBaaSNotarization[txidOfNotarization].proofroots.push(_notarization.proofroots[i]);
        }  

        for (uint i = 0; i < _notarization.nodes.length; i++) {
 
            PBaaSNotarization[txidOfNotarization].nodes.push(_notarization.nodes[i]);
        }  

        lastNotarizationTxid = txidOfNotarization;
       
    }

    function setbestFork(VerusObjectsNotarization.NotarizationForks memory proof) public 
    {
        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        bestForks.push(proof);
    }

    function getbestFork(uint index) public view returns (VerusObjectsNotarization.NotarizationForks memory)
    {
        return bestForks[index];
    }

    function deletebestFork() public 
    {
        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        delete bestForks;
    }

    function bestForkLength() public view returns (uint256)
    {
        return bestForks.length;
    }

    function getLastNotarizationProposer() public view returns (address){

        address proposer;
        bytes memory proposerBytes = PBaaSNotarization[bestForks[0].txid.hash].proposer.destinationaddress;

            assembly {
                proposer := mload(add(proposerBytes,20))
            } 

        return proposer;

    }

}