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
    mapping (uint => uint) public exportHeights;
    address private upgradeContract;
    address private  verusBridge;
    address  private tokenManager;

    mapping (bytes32 => bool) public processedTxids;
    mapping (address => VerusObjects.mappedToken) private verusToERC20mapping;
    mapping (bytes32 => VerusObjects.lastImportInfo) public lastImportInfo;

    address[] public tokenList;
    bytes32 public lastTxIdImport;

    uint64 public cceLastStartHeight;
    uint64 public cceLastEndHeight;
   
    constructor (address upgradeContractAddress){

        upgradeContract = upgradeContractAddress;
        VerusNft t = new VerusNft(); 

        verusToERC20mapping[VerusConstants.VerusNFTID] = 
            VerusObjects.mappedToken(address(t), uint8(VerusConstants.MAPPING_VERUS_OWNED + VerusConstants.TOKEN_ETH_NFT_DEFINITION),
                0, "VerusNFT", uint256(0));  

        tokenList.push(VerusConstants.VerusNFTID);
    }

    function setContracts(address[13] memory contracts) public {
        
        require(msg.sender == upgradeContract);

        tokenManager = contracts[uint(VerusConstants.ContractType.TokenManager)];
        verusBridge = contracts[uint(VerusConstants.ContractType.VerusBridge)];
    }

    function upgradeTokens(address newBridgeStorageAddress) public {
        
        require(msg.sender == upgradeContract);

        VerusNft(verusToERC20mapping[VerusConstants.VerusNFTID].erc20ContractAddress).changeowner(newBridgeStorageAddress);
        
        for (uint i = 0; i < tokenList.length ; i++) {
            if (verusToERC20mapping[tokenList[i]].flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) {
                Token(verusToERC20mapping[tokenList[i]].erc20ContractAddress).changeowner(newBridgeStorageAddress);
            }
        }
    }

    function isSenderBridgeContract(address sender) private view {

        require(sender == verusBridge);
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
            revert();
        }
    }

    function setReadyExportTransfers(uint64 _startHeight, uint64 _endHeight, VerusObjects.CReserveTransfer memory reserveTransfer, uint blockTxLimit) public {

        isSenderBridgeContract(msg.sender);
        
        _readyExports[_startHeight].endHeight = _endHeight;
        _readyExports[_startHeight].transfers.push(reserveTransfer);
        require(_readyExports[_startHeight].transfers.length <= blockTxLimit);
      
    }

    function setReadyExportTxid(bytes32 txidhash, bytes32 prevTxidHash, uint _block) public {
        
        isSenderBridgeContract(msg.sender);
        
        _readyExports[_block].exportHash = txidhash;

        if (_readyExports[_block].transfers.length == 1)
        {
            _readyExports[_block].prevExportHash = prevTxidHash;

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
        returns(VerusObjects.CReserveTransferSet memory) {
        
        VerusObjects.CReserveTransferSet memory exportSet = _readyExports[_block];

        return exportSet;
    }

    function getTokenListLength() public view returns(uint) {

        return tokenList.length;
    }

    function ERC20Registered(address _iaddress) public view returns (bool) {

        return verusToERC20mapping[_iaddress].flags > 0;
        
    }

    function emitNewToken(string memory name, string memory ticker) public returns (address){

        require(msg.sender == address(tokenManager));
        Token t = new Token(name, ticker);   
        // emit TokenCreated(address(t));
        return address(t);
    }

    function mintNFT(address tokenId, string memory tokenURI, address recipient) public  {
        
        require(msg.sender == address(tokenManager));
        VerusNft t = VerusNft(verusToERC20mapping[VerusConstants.VerusNFTID].erc20ContractAddress);
        t.mint(tokenId, tokenURI, recipient);
    }

    function mintOrTransferToken(Token token, address destinationAddress, uint256 amount, bool mint ) public {

        require(address(tokenManager) == msg.sender);

            if (mint) 
            {   
                token.mint(destinationAddress, amount);
            } 
            else 
            {
                (bool success, ) = address(token).call(abi.encodeWithSignature("transfer(address,uint256)", destinationAddress, amount));
                require(success, "transfer of token failed");
            }
    }

    function transferETHNft (address ercContractAddress, address destination, uint256 tokenID) public {
        
        require(address(tokenManager) == msg.sender);
        ERC721(ercContractAddress).transferFrom(address(this), destination, tokenID);
    }

    function exportERC20Tokens(uint256 _tokenAmount, Token token, bool burn, address sender ) public {
        
        require(msg.sender == verusBridge);
        (bool success, ) = address(token).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, address(this), _tokenAmount));
        require(success, "transferfrom of token failed");

        if (burn) 
        {
            token.burn(_tokenAmount);
        }
    }

    function setCceHeights(uint64 start, uint64 end) public {

        require (msg.sender == verusBridge);
        cceLastStartHeight = start;
        cceLastEndHeight = end;
    }

}