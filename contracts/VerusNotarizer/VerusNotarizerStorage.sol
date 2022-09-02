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
  
    VerusObjectsNotarization.NotarizationProofs[] public bestProofs;
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

    function setNotarization(VerusObjectsNotarization.CPBaaSNotarization memory _notarization, bytes32 hashOfNotarization) public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        
        // copying from memory to storage cannot be done directly


        PBaaSNotarization[hashOfNotarization].version = _notarization.version; 
        PBaaSNotarization[hashOfNotarization].flags = _notarization.flags;
        PBaaSNotarization[hashOfNotarization].proposer = _notarization.proposer;
        PBaaSNotarization[hashOfNotarization].currencystate = _notarization.currencystate;
        PBaaSNotarization[hashOfNotarization].notarizationheight = _notarization.notarizationheight;
        PBaaSNotarization[hashOfNotarization].prevnotarization = _notarization.prevnotarization;
        PBaaSNotarization[hashOfNotarization].hashprevnotarization = _notarization.hashprevnotarization;
        PBaaSNotarization[hashOfNotarization].prevheight = _notarization.prevheight;
        PBaaSNotarization[hashOfNotarization].txid = _notarization.txid;

        for (uint i = 0; i < _notarization.currencystates.length; i++) {
 
            PBaaSNotarization[hashOfNotarization].currencystates.push(_notarization.currencystates[i]);
        }  
              
        for (uint i = 0; i < _notarization.proofroots.length; i++) {
 
            PBaaSNotarization[hashOfNotarization].proofroots.push(_notarization.proofroots[i]);
        }  

        for (uint i = 0; i < _notarization.nodes.length; i++) {
 
            PBaaSNotarization[hashOfNotarization].nodes.push(_notarization.nodes[i]);
        }  

        lastNotarizationTxid = _notarization.txid.hash;
       
    }

    function setBestProof(VerusObjectsNotarization.NotarizationProofs memory proof) public 
    {
        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        bestProofs.push(proof);
    }

    function getBestProof(uint index) public view returns (VerusObjectsNotarization.NotarizationProofs memory)
    {
        return bestProofs[index];
    }

    function deleteBestProof() public 
    {
        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        delete bestProofs;
    }

    function bestProofLength() public view returns (uint256)
    {
        return bestProofs.length;
    }

    function getLastNotarizationProposer() public view returns (address){

        address proposer;
        bytes memory proposerBytes = PBaaSNotarization[bestProofs[0].hashOfNotarization].proposer.destinationaddress;

            assembly {
                proposer := mload(add(proposerBytes,20))
            } 

        return proposer;

    }

}