// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";

import "./TokenManager.sol";    
import "./VerusSerializer.sol";
import "../MMR/VerusProof.sol";
import "./VerusCrossChainExport.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusBridge.sol";
import "./VerusInfo.sol";
import "./ExportManager.sol";

contract VerusBridgeMaster {

    //declare the contracts and have it return the contract addresses

    VerusBridge verusBridge;
    VerusNotarizer verusNotarizer;
    VerusInfo verusInfo;
    address[8] contracts;

    //temporary placeholder for testing purposes
    address contractOwner;
    
    //all major functions get declared here and passed through to the underlying contract
    uint256 feesHeld = 0;
    uint256 ethHeld = 0;
    uint256 poolSize = 0;

    mapping (address => uint256) public claimableFees;

    // used to prove the transfers the index of this corresponds to the index of the 
    bytes32[] public readyExportHashes;

    // DO NOT ADD ANY VARIABLES ABOVE THIS POINT
    // used to store a list of currencies and an amount
    // VerusObjects.CReserveTransfer[] private _pendingExports;
    
    // stores the blockheight of each pending transfer
    // the export set holds the summary of a set of exports
    mapping (uint => VerusObjects.exportSet) public _readyExports;
    
    //stores the index corresponds to the block
    VerusObjects.LastImport public lastimport;
    mapping (bytes32 => bool) public processedTxids;
    mapping (uint => VerusObjects.blockCreated) public readyExportsByBlock;
    
    uint public lastTxImportHeight;


    
    //contract allows the contracts to be set and reset
    constructor(
        uint256 _poolSize){
            contractOwner = msg.sender; 
            poolSize = _poolSize;        
    }
    
    /** get and set functions, sets to be performed by the notariser **/
    function setContractAddress(VerusConstants.ContractType contractTypeAddress, address _newContractAddress) public {
        assert(msg.sender == contractOwner);

        contracts[uint(contractTypeAddress)] = _newContractAddress;

        if(contractTypeAddress == VerusConstants.ContractType.VerusNotarizer){
            verusNotarizer = VerusNotarizer(_newContractAddress);       
        }        
        else if(contractTypeAddress == VerusConstants.ContractType.VerusBridge){
            verusBridge = VerusBridge(_newContractAddress);       
        }
        else if(contractTypeAddress == VerusConstants.ContractType.VerusInfo){
            verusInfo = VerusInfo(_newContractAddress);       
        }
    }
    
    /** returns the address of each contract to be used by the sub contracts **/
    function getContractAddress(VerusConstants.ContractType contractTypeAddress) public view returns(address contractAddress){
        
        contractAddress = contracts[uint(contractTypeAddress)];

    }

    function setFeesHeld(uint256 _feesAmount) public {
        require( msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        feesHeld = _feesAmount;
    }
    function getFeesHeld() public view returns(uint256){
        return feesHeld;
    }
    function addToFeesHeld(uint256 _feesAmount) public {
        require( msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        feesHeld += _feesAmount;
    }

    function addToEthHeld(uint256 _ethAmount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        ethHeld += _ethAmount;
    }
    function subtractFromEthHeld(uint256 _ethAmount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        ethHeld -= _ethAmount;
    }

    function setEthHeld(uint256 _ethAmount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        ethHeld = _ethAmount;
    }

    function getEthHeld() public view returns(uint256){
        return ethHeld;
    }

    function setPoolSize(uint256 _amount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        ethHeld = _amount;
    }

    function getPoolSize() public view returns(uint256){
        return poolSize;
    }

    function setClaimableFees(address _feeRecipient,uint256 _ethAmount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        claimableFees[_feeRecipient] = claimableFees[_feeRecipient] + _ethAmount;
    }

    /** VerusBridge pass through functions **/
    function export(VerusObjects.CReserveTransfer memory _transfer) public payable {
        uint256 ethAmount = msg.value;
        verusBridge.export(_transfer, ethAmount);
    }

    function checkImports(bytes32[] memory _imports) public view returns(bytes32[] memory){
        return verusBridge.checkImports(_imports);
    }

    function submitImports(VerusObjects.CReserveTransferImport[] memory _imports) public {
        verusBridge.submitImports(_imports);
    }

    function getReadyExportsByRange(uint _startBlock, uint _endBlock) public view 
        returns(VerusObjects.CReserveTransferSet[] memory){
        return verusBridge.getReadyExportsByRange(_startBlock,_endBlock);
    }

    /** VerusNotarizer pass through functions **/

    function poolAvailable(address _address) public view returns(bool){
        uint32 heightAvailable = verusNotarizer.poolAvailable(_address);
        return heightAvailable != 0 && heightAvailable < block.number;
    }

    function getLastProofRoot() public view returns(VerusObjectsNotarization.CProofRoot memory){
        return verusNotarizer.getLastProofRoot();
    }

    function lastBlockHeight() public view returns(uint32){
        return verusNotarizer.lastBlockHeight();
    }

    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization,
        uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddress
        ) public returns(bool){
            return verusNotarizer.setLatestData(_pbaasNotarization,_vs,_rs,_ss,blockheights,notaryAddress);
    }

    /** VerusInfo pass through functions **/

     function getinfo() public view returns(VerusObjects.infoDetails memory){
         return verusInfo.getinfo();
     }

     function sendEth(uint256 _ethAmount, address payable _ethAddress) public {
         //only callable by verusbridge contract
        require(msg.sender == address(verusBridge),"Sorry you can't call this function");
        _ethAddress.transfer(_ethAmount);
     }


}