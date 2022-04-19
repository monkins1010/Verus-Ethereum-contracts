// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./Token.sol";
import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "./VerusBridgeMaster.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./TokenManager.sol";


contract VerusBridgeStorage {

    mapping (uint => VerusObjects.CReserveTransferSet) public _readyExports;

    address upgradeContract;
    address verusBridge;
    TokenManager tokenManager;
    address verusBridgeMaster;

  //  event TokenCreated(address tokenAddress);

    //all major functions get declared here and passed through to the underlying contract
    //uint256 feesHeld = 0;
    uint256 ethHeld = 0;

    // VRSC pool size in WEI
    uint256 poolSize = 0;  

    mapping (bytes32 => bool) public processedTxids;
    mapping (address => VerusObjects.mappedToken) public verusToERC20mapping;
    address[] public tokenList;
    
    uint public lastTxImportHeight;
    uint32 public firstBlock;
    uint32 public lastCCEExportHeight;
   
    //contract allows the contracts to be set and reset
    constructor(
        address upgradeContractAddress, uint256 _poolSize){
        upgradeContract = upgradeContractAddress;     
        poolSize = _poolSize;   
        firstBlock = uint32(block.number);
    }

    function setContracts(address[12] memory contracts) public {
        
        //TODO: Make updating contract a multisig check across 3 notaries.(change in VerusBridgeMaster.)
        require(msg.sender == upgradeContract);

        if(contracts[uint(VerusConstants.ContractType.TokenManager)] != address(tokenManager))
        {
            tokenManager = TokenManager(contracts[uint(VerusConstants.ContractType.TokenManager)]);
        } 
        
        if(contracts[uint(VerusConstants.ContractType.VerusBridge)] != verusBridge)
        {
            verusBridge = contracts[uint(VerusConstants.ContractType.VerusBridge)];
        } 

    }

    function isSenderBridgeContract(address sender) private view {

        require( sender == verusBridge);
    }

    /* function addToFeesHeld(uint256 _feesAmount) public {
        isSenderBridgeContract(msg.sender);
        feesHeld += _feesAmount;
    } */

    function addToEthHeld(uint256 _ethAmount) public {
        isSenderBridgeContract(msg.sender);
        ethHeld += _ethAmount;
    }

    function subtractFromEthHeld(uint256 _ethAmount) public {
        require( msg.sender == verusBridge || msg.sender == address(tokenManager));
        ethHeld -= _ethAmount;
    }

    function subtractPoolSize(uint256 _amount) public returns (bool){
        isSenderBridgeContract(msg.sender);
        if(_amount > poolSize) return false;
        poolSize -= _amount;
        return true;
    }

    function setReadyExportTransfers(uint _block, VerusObjects.CReserveTransfer memory reserveTransfer) public returns (bool){

        isSenderBridgeContract(msg.sender);
        
      //  VerusObjects.CReserveTransfer memory reserveTX = reserveTransfer;
        _readyExports[_block].blockHeight = uint32(_block);
        _readyExports[_block].transfers.push(reserveTransfer);

        return (_readyExports[_block].transfers.length == 1);
    
    }

    function setReadyExportTxid(bytes32 txidhash, bytes32 prevTxidHash) public {
        
        isSenderBridgeContract(msg.sender);
        uint _block = block.number;
        
        _readyExports[_block].exportHash = txidhash;

        if (_readyExports[_block].transfers.length == 1)
        {
            _readyExports[_block].prevExportHash = prevTxidHash;
            lastCCEExportHeight = uint32(_block);
        }
    
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

      //REMOVE:  require( msg.sender == tokenManager);
        verusToERC20mapping[iaddress] = mappedToken;

    }

    function getReadyExports(uint _block) public view
        returns(VerusObjects.CReserveTransferSet memory){
        
        VerusObjects.CReserveTransferSet memory exportSet = _readyExports[_block];

        return exportSet;
    }

    function getTokenListLength() public view returns(uint) {

        return tokenList.length;

    }

    function pushTokenList(address iaddress) public {

        require(msg.sender == address(tokenManager));

        return tokenList.push(iaddress);

    }

    function ERC20Registered(address _iaddress) public view returns (bool) {

        return verusToERC20mapping[_iaddress].flags > 0;
        
    }

    function checkiaddresses(VerusObjects.CReserveTransfer memory transfer) public view {

        require(ERC20Registered(transfer.currencyvalue.currency) && 
        ERC20Registered(transfer.feecurrencyid) &&
        ERC20Registered(transfer.destcurrencyid) &&
        (ERC20Registered(transfer.secondreserveid) || 
        transfer.secondreserveid == address(0)) &&
        transfer.destsystemid == address(0));
    }


    function emitNewToken(string memory name, string memory ticker, address _iaddress) public returns (address){

        require(msg.sender == address(tokenManager));
        Token t = new Token(name, ticker);   
        tokenList.push(_iaddress); 
      //  emit TokenCreated(address(t));
        return address(t);

    }
/*
    function mintOrTransferToken(address _destination, uint256 processedTokenAmount, uint32 flags, Token token ) public {

        require(msg.sender == tokenManager, "Only tokenmanager allowed to mintOrTransferToken");
        if(_destination != address(0))
        {
            if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) 
            {   
                token.mint(_destination, processedTokenAmount);
            } 
            else 
            {
                token.transfer(_destination, processedTokenAmount);
            }
        }
    }
*/
    function importTransactions(
        VerusObjects.PackedSend[] calldata trans,
        uint8[] memory transferLocations
    ) public  {
      //REMOVE:  require(
     //       tokenManager == msg.sender,
     //       "importERC20Tokens:bridgecontractonly");

        uint32 flags;
        address ERC20Address;

        for(uint256 i = 0; i < transferLocations.length; i++)
        {
            flags = verusToERC20mapping[address(uint160(trans[transferLocations[i]].currencyAndAmount))].flags;
            ERC20Address = verusToERC20mapping[address(uint160(trans[transferLocations[i]].currencyAndAmount))].erc20ContractAddress;

            Token token = Token(ERC20Address);

            address destinationAddress;

            destinationAddress  = address(uint160(trans[transferLocations[i]].destinationAndFlags));
            
            if(destinationAddress != address(0))
            {
        
                uint256 converted;

                converted = convertFromVerusNumber(trans[transferLocations[i]].currencyAndAmount >> 160, token.decimals());

                if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) 
                {   
                    token.mint(destinationAddress, converted);
                } 
                else 
                {
                    token.transfer(destinationAddress, converted);
                }
            }
            
           
        }
            
    }

    
    function exportERC20Tokens(uint256 _tokenAmount, Token token, bool burn, address sender ) public {
        
        require(msg.sender == verusBridge);

        token.transferFrom(sender, address(this), _tokenAmount);

        if (burn) 
        {
            token.burn(_tokenAmount);
        }
    }

    function convertFromVerusNumber(uint256 a,uint8 decimals) public pure returns (uint256) {
        uint8 power = 10; //default value for 18
        uint256 c = a;

        if(decimals > 8 ) {
            power = decimals - 8;// number of decimals in verus
            c = a * (10 ** power);
        }else if(decimals < 8){
            power = 8 - decimals;// number of decimals in verus
            c = a / (10 ** power);
        }
      
        return c;
    }

}