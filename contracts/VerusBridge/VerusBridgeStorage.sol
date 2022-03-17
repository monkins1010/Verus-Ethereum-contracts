// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "./VerusBridgeMaster.sol";

contract VerusBridgeStorage {

    address verusBridgeMaster;
    address verusBridge;
    address tokenManager;

    //all major functions get declared here and passed through to the underlying contract
    uint256 feesHeld = 0;
    uint256 ethHeld = 0;

    // VRSC pool size in WEI
    uint256 poolSize = 0;  

    mapping (address => uint256) public claimableFees;
    mapping (uint => VerusObjects.exportSet) public _readyExports;
    mapping (bytes32 => bool) public processedTxids;
    mapping (address => VerusObjects.mappedToken) public verusToERC20mapping;
    address[] public tokenList;
    
    uint public lastTxImportHeight;
    uint256 public firstBlock;

    
    //contract allows the contracts to be set and reset
    constructor(
        address bridgeMasterAddress, uint256 _poolSize){
        verusBridgeMaster = bridgeMasterAddress;   
        poolSize = _poolSize;
        firstBlock = block.number;    
    }

    function setContracts(address[10] memory contracts) public {
        
        //TODO: Make updating contract a multisig check across 3 notaries.
        assert(msg.sender == verusBridgeMaster);

         if(contracts[uint(VerusConstants.ContractType.TokenManager)] != tokenManager){
            tokenManager = contracts[uint(VerusConstants.ContractType.TokenManager)];
         } 
        
        if(contracts[uint(VerusConstants.ContractType.VerusBridge)] != verusBridge){
            verusBridge = contracts[uint(VerusConstants.ContractType.VerusBridge)];
         } 
      

    }
    
    function isSenderBridgeContract(address sender) private view {

        require( sender == verusBridge,"Storage requires Bridge");
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

    function setClaimableFees(address _feeRecipient,uint256 _ethAmount) public {
        isSenderBridgeContract(msg.sender);
        claimableFees[_feeRecipient] = claimableFees[_feeRecipient] + _ethAmount;
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

    function getERCMapping(address iaddress)public view returns (VerusObjects.mappedToken memory) {

        return verusToERC20mapping[iaddress];

    }
    function RecordverusToERC20mapping(address iaddress, VerusObjects.mappedToken memory mappedToken) public {

        assert( msg.sender == tokenManager);
        verusToERC20mapping[iaddress] = mappedToken;

    }

    function getReadyExports(uint _block) public view
        returns(VerusObjects.exportSet memory){
        
        VerusObjects.exportSet memory exportSet = _readyExports[_block];

        return exportSet;
    }

    function getTokenListLength() public view returns(uint) {

        return tokenList.length;

    }

    function pushTokenList(address iaddress) public {

        assert(msg.sender == tokenManager);

        return tokenList.push(iaddress);

    }

}