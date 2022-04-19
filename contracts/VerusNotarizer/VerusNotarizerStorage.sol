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
  
    uint32 public lastBlockHeight;
    mapping (address => uint256) public claimableFees;
    
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

    function setPoolAvailable(uint32 height, address currency) public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        poolAvailable[currency] = height; 

    }

    function getNotarization(uint32 height) public view returns (VerusObjectsNotarization.CPBaaSNotarization memory){

        return PBaaSNotarization[height];

    }

    function setNotarization(VerusObjectsNotarization.CPBaaSNotarization memory _notarization, uint32 verusHeight) public {

        require( msg.sender == verusNotarizer,"setNotarizedProof:callfromNotarizeronly");
        
        // copying from memeory to storage cannot be done directly
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

        lastBlockHeight = verusHeight;

    }

    function getLastProofRoot() public view returns(VerusObjectsNotarization.CProofRoot memory){

        for (uint i=0; i< PBaaSNotarization[lastBlockHeight].proofroots.length; i++)
        {
            if (PBaaSNotarization[lastBlockHeight].proofroots[i].systemid == VerusConstants.VerusCurrencyId) 
            {
                return PBaaSNotarization[lastBlockHeight].proofroots[i];
            }
        }

        VerusObjectsNotarization.CProofRoot[] memory proofRoot = new VerusObjectsNotarization.CProofRoot[](1);
        return proofRoot[0];
    }

    function getLastNotarizationProposer() public view returns (address){

        address proposer;
        bytes memory proposerBytes = PBaaSNotarization[lastBlockHeight].proposer.destinationaddress;

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