// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "./Token.sol";
import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";



contract VerusBridgeStorage {

    mapping (uint => VerusObjects.CReserveTransferSet) public _readyExports;

    address upgradeContract;
    address verusBridge;
    address tokenManager;

   // VRSC pool size in sats

    mapping (bytes32 => bool) public processedTxids;
    mapping (address => VerusObjects.mappedToken) public verusToERC20mapping;
    mapping (bytes32 => VerusObjects.lastImportInfo) public lastImportInfo;
    address[] public tokenList;
    
    bytes32 public lastTxIdImport;

    uint32 public lastCCEExportHeight;
   
    //  contract allows the contracts to be set and reset
    constructor(
        address upgradeContractAddress){
        upgradeContract = upgradeContractAddress;     

    }

    function setContracts(address[12] memory contracts) public {
        
        require(msg.sender == upgradeContract);

        tokenManager = contracts[uint(VerusConstants.ContractType.TokenManager)];

        verusBridge = contracts[uint(VerusConstants.ContractType.VerusBridge)];
    }

    function isSenderBridgeContract(address sender) private view {

        require( sender == verusBridge);
    }

    function setLastImport(bytes32 processedTXID, bytes32 hashofTXs, uint128 CCEheightsandTXNum ) public {

        isSenderBridgeContract(msg.sender);
        processedTxids[processedTXID] = true;
        lastTxIdImport = processedTXID;
        lastImportInfo[processedTXID] = VerusObjects.lastImportInfo(hashofTXs, processedTXID, uint32(CCEheightsandTXNum >> 64), uint32(CCEheightsandTXNum >> 32));
    } 

    function isLastCCEInOrder(uint32 height) public view  {
      
        if ((lastImportInfo[lastTxIdImport].height + 1) == height)
        {
            return;
        } 
        else if (lastTxIdImport == bytes32(0))
        {
            return;
        } 
        else{
            revert("CCE Out of order");
        }
    }

    function setReadyExportTransfers(uint _block, VerusObjects.CReserveTransfer memory reserveTransfer) public returns (bool){

        isSenderBridgeContract(msg.sender);
        
        _readyExports[_block].blockHeight = uint32(_block);
        _readyExports[_block].transfers.push(reserveTransfer);

        return (_readyExports[_block].transfers.length == 1);
    
    }

    function setReadyExportTxid(bytes32 txidhash, bytes32 prevTxidHash, uint _block) public {
        
        isSenderBridgeContract(msg.sender);
        
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

    function getERCMapping(address iaddress)public view returns (VerusObjects.mappedToken memory) {

        return verusToERC20mapping[iaddress];

    }
    function RecordTokenmapping(address iaddress, VerusObjects.mappedToken memory mappedToken) public {

        require( msg.sender == address(tokenManager));
        tokenList.push(iaddress);
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


    function emitNewToken(string memory name, string memory ticker) public returns (address){

        require(msg.sender == address(tokenManager));
        Token t = new Token(name, ticker);   
        // emit TokenCreated(address(t));
        return address(t);

    }

    function importTransactions(
        VerusObjects.PackedSend[] calldata trans) public  
    {
      
        require(address(tokenManager) == msg.sender);

        uint32 ERCflags;
        uint32 sendFlags;
        address ERCAddress;
        Token token;
        for(uint256 i = 0; i < trans.length; i++)
        {
            ERCflags = verusToERC20mapping[address(uint160(trans[i].currencyAndAmount))].flags;
            ERCAddress = verusToERC20mapping[address(uint160(trans[i].currencyAndAmount))].erc20ContractAddress;
            //TODO: The token could be a NFT so mint or send it. add in logic to handle
            address destinationAddress;
            destinationAddress  = address(uint160(trans[i].destinationAndFlags));
            sendFlags = uint32(trans[i].destinationAndFlags >> 160);

            if (sendFlags & VerusConstants.TOKEN_ERC20_SEND == VerusConstants.TOKEN_ERC20_SEND  &&
                   ERCflags & VerusConstants.TOKEN_LAUNCH == VerusConstants.TOKEN_LAUNCH )
            {
                token = Token(ERCAddress);
                
                if(destinationAddress != address(0))
                {
                    uint256 converted;

                    converted = convertFromVerusNumber(trans[i].currencyAndAmount >> 160, token.decimals());

                    if (ERCflags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) 
                    {   
                        token.mint(destinationAddress, converted);
                    } 
                    else 
                    {
                        token.transfer(destinationAddress, converted);
                    }
                }
            } else if (ERCflags & VerusConstants.TOKEN_ETH_NFT_DEFINITION == VerusConstants.TOKEN_ETH_NFT_DEFINITION)
            {
                uint256 tokenID = verusToERC20mapping[address(uint160(trans[i].currencyAndAmount))].tokenID;
                if(destinationAddress != address(0))
                    ERC721(ERCAddress).transferFrom(address(this), destinationAddress, tokenID);

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