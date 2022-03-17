// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.20;
pragma experimental ABIEncoderV2;

import "./Token.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjects.sol";
import "./VerusSerializer.sol";
import "../VerusBridge/VerusBridge.sol";
import "../VerusBridge/VerusBridgeMaster.sol";
import "../VerusBridge/VerusBridgeStorage.sol";
import "../Libraries/VerusObjectsCommon.sol";


contract TokenManager {

    event TokenCreated(address tokenAddress);
    
    VerusBridgeMaster verusBridgeMaster;
    VerusSerializer verusSerializer;
    VerusBridgeStorage verusBridgeStorage;

    constructor(
        address verusBridgeMasterAddress,
        address verusBridgeStorageAddress,
        address verusSerializerAddress
    ) {
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress);
        verusBridgeStorage = VerusBridgeStorage(verusBridgeStorageAddress); 
        verusSerializer = VerusSerializer(verusSerializerAddress);
    }
    
    function setContract(address contractAddress) public {

        assert(msg.sender == address(verusBridgeMaster));
        verusSerializer = VerusSerializer(contractAddress);
    }

    function verusToERC20mapping(address iaddress) public view returns (VerusObjects.mappedToken memory) {

        VerusObjects.mappedToken memory mappingData = verusBridgeStorage.getERCMapping(iaddress);
        return mappingData;
    }

    function getTokenList() public view returns(VerusObjects.setupToken[] memory ) {

        uint tokenListLength;
        tokenListLength = verusBridgeStorage.getTokenListLength();
        VerusObjects.setupToken[] memory temp = new VerusObjects.setupToken[](tokenListLength);

        for(uint i=0; i< tokenListLength; i++) {

            address tokenAddress;
            tokenAddress = verusBridgeStorage.tokenList(i);

            temp[i].iaddress = tokenAddress;
            temp[i].erc20ContractAddress = verusToERC20mapping(tokenAddress).erc20ContractAddress;
            temp[i].name = verusToERC20mapping(tokenAddress).name;
            temp[i].ticker = verusToERC20mapping(tokenAddress).ticker;
            temp[i].flags = verusToERC20mapping(tokenAddress).flags;
            temp[i].launchSystemID = verusToERC20mapping(tokenAddress).launchSystemID;
        }

        return temp;
    }
  
    function isVerusBridgeContract(address sender) private view returns (bool) {
       
       return sender == verusBridgeMaster.contracts(uint(VerusConstants.ContractType.TokenManager));

    }

    //Tokens that are being exported from the eth blockchain are either destroyed or held until imported
    function exportERC20Tokens(address _iaddress, uint256 _tokenAmount) public {
        require(
            isVerusBridgeContract(msg.sender),
            "Call can only be made from Verus Bridge Contract"
        );
        //check that the erc20 token is registered with the tokenManager
        VerusObjects.mappedToken memory mappedContract = verusToERC20mapping(_iaddress);

        require(mappedContract.erc20ContractAddress != address(0), "Token has not been registered yet");

        Token token = Token(mappedContract.erc20ContractAddress);

        //transfer the tokens to the contract address
        uint256 allowedTokens = token.allowance(msg.sender, address(this));
        require(
            allowedTokens >= _tokenAmount,              //values in wei
            "Not enough tokens have been approved"
        ); 
        //if its not approved it wont work
        token.transferFrom(msg.sender, address(this), _tokenAmount);

        if (mappedContract.flags & 
              VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) {

            require(token.balanceOf(address(this)) >= _tokenAmount,
                "Tokens didn't transfer"
            );
            token.burn(_tokenAmount);

        } else {
            //the contract stores the token
        }
    }

    function importERC20Tokens(
        address _iaddress,
        uint64 _tokenAmount,
        address _destination
    ) public {
        require(
            isVerusBridgeContract(msg.sender),
            "Call can only be made from Verus Bridge Contract"
        );
        address contractAddress;
        VerusObjects.mappedToken memory mappedContract = verusToERC20mapping(_iaddress);

        // if token that has been sent from verus is not registered on ETH burn the tokens
        if (ERC20Registered(_iaddress)) {
            contractAddress = mappedContract.erc20ContractAddress;

            Token token = Token(contractAddress);
            uint256 processedTokenAmount;
             convertFromVerusNumber(
                _tokenAmount,
                token.decimals()
            );
            //if the token has been created by this contract then burn the token
            if (mappedContract.flags & 
              VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) {

                token.mint(address(_destination), processedTokenAmount);

            } else {
                //transfer from the contract
                token.transfer(address(_destination), processedTokenAmount);
            }
        }
    }

    function ERC20Registered(address _iaddress) public view returns (bool) {

        return verusToERC20mapping(_iaddress).erc20ContractAddress != address(0);
        
    }

    function getSymbol(string memory _text)
        private
        pure
        returns (string memory)
    {
        bytes memory copy = new bytes(bytes(_text).length < VerusConstants.TICKER_LENGTH_MAX ? bytes(_text).length : VerusConstants.TICKER_LENGTH_MAX);
        bytes memory textAsBytes = bytes(_text);
        uint256 max = (
            textAsBytes.length > VerusConstants.TICKER_LENGTH_MAX
                ? VerusConstants.TICKER_LENGTH_MAX
                : uint8(textAsBytes.length)
        ) + 31;
        for (uint256 i = 32; i <= max; i += 32) {
            assembly {
                mstore(add(copy, i), mload(add(textAsBytes, i)))
            }
        }
        return string(copy);
    }

    function sha256d(bytes32 _bytes) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(sha256(abi.encodePacked(_bytes))));
    }

    function sha256d(string memory _string) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(sha256(abi.encodePacked(_string))));
    }

    function sha256d(bytes memory _bytes) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(sha256(abi.encodePacked(_bytes))));
    }

    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint256 i = 0; i < bStr.length; i++) {
            // Uppercase character...
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                // So we add 32 to make it lowercase
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }

    function getIAddress(VerusObjects.CcurrencyDefinition memory _ccd) public pure returns (address){

        if(_ccd.parent == address(0)) {
            return address(ripemd160(abi.encodePacked(sha256(abi.encodePacked(sha256d(_toLower(_ccd.name)))))));
        }
        else {
            return address(ripemd160(abi.encodePacked(sha256(abi.encodePacked(sha256d(abi.encodePacked(_ccd.parent,sha256d(_toLower(_ccd.name)))))))));
        }
    }

    function deployToken(bytes memory _serializedCcd) public  {
        
        require (isVerusBridgeContract(msg.sender),"Call can only be made from Verus Bridge Contract");

        VerusObjects.CcurrencyDefinition memory ccd = verusSerializer.deSerializeCurrencyDefinition(_serializedCcd);
        address destinationCurrencyID = getIAddress(ccd);

        if (ERC20Registered(destinationCurrencyID))
            return;

        uint8 currencyFlags;

        if (ccd.systemID != VerusConstants.VEth) 
            currencyFlags = VerusConstants.MAPPING_VERUS_OWNED;

        recordToken(destinationCurrencyID, ccd.nativeCurrencyID, ccd.name, getSymbol(ccd.name), currencyFlags, ccd.launchSystemID);
    }


    function launchTokens(VerusObjects.setupToken[] memory tokensToDeploy) public  {

        require(verusBridgeStorage.getERCMapping(VerusConstants.VEth).erc20ContractAddress == address(0), "Launch tokens already set");

        for (uint256 i = 0; i < tokensToDeploy.length; i++) {
            recordToken(
                tokensToDeploy[i].iaddress,
                tokensToDeploy[i].erc20ContractAddress,
                tokensToDeploy[i].name,
                tokensToDeploy[i].ticker,
                tokensToDeploy[i].flags,
                tokensToDeploy[i].launchSystemID
            );
        }
    }

    function recordToken(
        address _iaddress,
        address ethContractAddress,
        string memory name,
        string memory ticker,
        uint8 flags,
        address launchSystemID
    ) private returns (address) {

        address ERCContract;

        if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED ) {

            Token t = new Token(name, ticker);   
            ERCContract = address(t);
            verusBridgeStorage.pushTokenList(_iaddress); 
            emit TokenCreated(ERCContract);

        } else {

            ERCContract = ethContractAddress;
            verusBridgeStorage.pushTokenList(_iaddress);

        }
        
        verusBridgeStorage.RecordverusToERC20mapping(_iaddress, VerusObjects.mappedToken(ERCContract, flags, name, ticker, verusBridgeStorage.getTokenListLength(), launchSystemID));
        return ERCContract;
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

    function convertToVerusNumber(uint256 a,uint8 decimals) public pure returns (uint256) {
         uint8 power = 10; //default value for 18
         uint256 c = a;
        if(decimals > 8 ) {
            power = decimals - 8;// number of decimals in verus
            c = a / (10 ** power);
        }else if(decimals < 8){
            power = 8 - decimals;// number of decimals in verus
            c = a * (10 ** power);
        }
      
        return c;
    }
}