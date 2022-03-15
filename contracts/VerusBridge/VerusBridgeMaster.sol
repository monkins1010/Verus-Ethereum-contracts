// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";

import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusBridge.sol";
import "./VerusInfo.sol";

contract VerusBridgeMaster {

    //declare the contracts and have it return the contract addresses

    VerusBridge verusBridge;
    VerusNotarizer verusNotarizer;
    VerusInfo verusInfo;
    
    // Total amount of contracts.
    address[8] contracts;

    //temporary placeholder for testing purposes
    address contractOwner;
    
    //all major functions get declared here and passed through to the underlying contract
    uint256 feesHeld = 0;
    uint256 ethHeld = 0;

    // VRSC pool size in WEI
    uint256 poolSize = 0;  

    mapping (address => uint256) public claimableFees;
    mapping (uint => VerusObjects.exportSet) public _readyExports;
    mapping (bytes32 => bool) public processedTxids;
    
    uint public lastTxImportHeight;
    uint256 public firstBlock;

    
    //contract allows the contracts to be set and reset
    constructor(
        uint256 _poolSize){
            contractOwner = msg.sender; 
            poolSize = _poolSize;
            firstBlock = block.number;        
    }
    
    /** get and set functions, sets to be performed by the notariser **/
    function setContractAddress(VerusConstants.ContractType contractType, address _newContractAddress) public {
        
        //TODO: Make updating contract a multisig check across 3 notaries.
        assert(msg.sender == contractOwner);

        contracts[uint(contractType)] = _newContractAddress;

        if(contractType == VerusConstants.ContractType.VerusNotarizer){
            verusNotarizer = VerusNotarizer(_newContractAddress);       
        }        
        else if(contractType == VerusConstants.ContractType.VerusBridge){
            verusBridge = VerusBridge(_newContractAddress);       
        }
        else if(contractType == VerusConstants.ContractType.VerusInfo){
            verusInfo = VerusInfo(_newContractAddress);       
        }
    }
    
    /** returns the address of each contract to be used by the sub contracts **/
    function getContractAddress(VerusConstants.ContractType contractType) public view returns(address contractAddress){
        
        contractAddress = contracts[uint(contractType)];

    }

    function isSenderBridgeContract(address sender) private view {

        require( sender == address(verusBridge),"This function can only be called by Verus Bridge");
    }

    function addToFeesHeld(uint256 _feesAmount) public {
        isSenderBridgeContract(msg.sender);
        feesHeld += _feesAmount;
    }

    function addToEthHeld(uint256 _ethAmount) public {
        isSenderBridgeContract(msg.sender);
        ethHeld += _ethAmount;
    }

    function subtractFromEthHeld(uint256 _ethAmount) public {
        isSenderBridgeContract(msg.sender);
        ethHeld -= _ethAmount;
    }

    function subtractPoolSize(uint256 _amount) public returns (bool){
        isSenderBridgeContract(msg.sender);
        if(_amount > poolSize) return false;
        poolSize -= _amount;
        return true;
    }

    function getPoolSize() public view returns(uint256){
        return poolSize;
    }

    function setClaimableFees(address _feeRecipient,uint256 _ethAmount) public {
        isSenderBridgeContract(msg.sender);
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

    function getReadyExports(uint _block) public view
        returns(VerusObjects.exportSet memory){
        
        VerusObjects.exportSet memory exportSet = _readyExports[_block];

        return exportSet;
    }

    function setReadyExportTransfers(uint _block, VerusObjects.CReserveTransfer memory reserveTransfer) public {

        isSenderBridgeContract(msg.sender);
        
        VerusObjects.CReserveTransfer memory reserveTX = reserveTransfer;

        _readyExports[_block].transfers.push(reserveTX);
    
    }

    function setReadyExportTxid(uint _block, bytes32 txidhash) public {
        
        isSenderBridgeContract(msg.sender);
        
        _readyExports[_block].txidhash = txidhash;
    
    }

    function getCreatedExport(uint createdBlock) public view returns (address) {

        if (_readyExports[createdBlock].transfers.length > 0)
            return  _readyExports[createdBlock].transfers[0].destcurrencyid;
        else
            return address(0);
        
    }

    function setProcessedTxids(bytes32 processedTXID) public {

        isSenderBridgeContract(msg.sender);
        processedTxids[processedTXID] = true;

    }

    function setlastTxImportHeight(uint importHeight) public {

        isSenderBridgeContract(msg.sender);

        lastTxImportHeight = importHeight;

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
        isSenderBridgeContract(msg.sender);
        _ethAddress.transfer(_ethAmount);
     }


}