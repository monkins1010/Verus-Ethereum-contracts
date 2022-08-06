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

    mapping (uint32 => VerusObjectsNotarization.CPBaaSNotarization) public PBaaSNotarization;
    mapping (address => uint32) public poolAvailable;
  
    uint32 public lastAcceptedBlockHeight;
    uint32 public lastReceivedBlockHeight;
    mapping (address => uint256) public claimableFees;
    mapping (address => uint256) public storageGlobal;
    mapping (uint32 => bytes32) public verusStateRoot;
    
    constructor(address upgradeContractAddress)
    {
        upgradeContract = upgradeContractAddress;     
    }

    function setContracts(address[12] memory contracts) public {
        
        require(msg.sender == upgradeContract);
        
        if(contracts[uint(VerusConstants.ContractType.VerusBridge)] != verusBridge){
            verusBridge = contracts[uint(VerusConstants.ContractType.VerusBridge)];
         } 

        if(contracts[uint(VerusConstants.ContractType.VerusNotarizer)] != verusNotarizer){
            verusNotarizer = contracts[uint(VerusConstants.ContractType.VerusNotarizer)];
         } 

    }

    function setPoolAvailable() public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        poolAvailable[VerusConstants.VerusBridgeAddress] = uint32(block.number); 

    }

    function pushStorageGlobal(address iaddress,uint256 data) public {

        require(msg.sender == address(verusBridge));

        storageGlobal[iaddress] = data;

    }

    function getNotarization(uint32 height) public view returns (VerusObjectsNotarization.CPBaaSNotarization memory){

        return PBaaSNotarization[height];

    }

    function setNotarization(VerusObjectsNotarization.CPBaaSNotarization memory _notarization) public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        
        // copying from memory to storage cannot be done directly

        uint32 verusHeight = lastReceivedBlockHeight = _notarization.notarizationheight;

        PBaaSNotarization[verusHeight].version = _notarization.version; 
        PBaaSNotarization[verusHeight].flags = _notarization.flags;
        PBaaSNotarization[verusHeight].proposer = _notarization.proposer;
        PBaaSNotarization[verusHeight].currencystate = _notarization.currencystate;
        PBaaSNotarization[verusHeight].notarizationheight = _notarization.notarizationheight;
        PBaaSNotarization[verusHeight].prevnotarization = _notarization.prevnotarization;
        PBaaSNotarization[verusHeight].hashprevnotarization = _notarization.hashprevnotarization;
        PBaaSNotarization[verusHeight].prevheight = _notarization.prevheight;

        for (uint i = 0; i < _notarization.currencystates.length; i++) {
 
            PBaaSNotarization[verusHeight].currencystates.push(_notarization.currencystates[i]);
        }  
              
        for (uint i = 0; i < _notarization.proofroots.length; i++) {
 
            PBaaSNotarization[verusHeight].proofroots.push(_notarization.proofroots[i]);
        }  

        for (uint i = 0; i < _notarization.nodes.length; i++) {
 
            PBaaSNotarization[verusHeight].nodes.push(_notarization.nodes[i]);
        }  

        // First notarization recieved is valid and this becomes the returned lastimportproof
        if(lastAcceptedBlockHeight == 0)
        {
            lastAcceptedBlockHeight = verusHeight;
        }
        // second notarization received is not put as the accepted yet until next n+1 notarization received
        else if (_notarization.prevheight != verusHeight)
        {
            lastAcceptedBlockHeight = _notarization.prevheight;
        }

    }

    function setVerusStateRoot(uint32 height, bytes32 stateroot) public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        verusStateRoot[height] = stateroot;
    }

    function getLastNotarizationProposer() public view returns (address){

        address proposer;
        bytes memory proposerBytes = PBaaSNotarization[lastAcceptedBlockHeight].proposer.destinationaddress;

            assembly {
                proposer := mload(add(proposerBytes,20))
            } 

        return proposer;

    }
    
    function setClaimedFees(address _address, uint256 fees)public returns (uint256)
    {
        require(msg.sender == verusNotarizer);

        claimableFees[_address] += fees;

        return claimableFees[_address];
    }

}