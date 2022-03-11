// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.20;
pragma experimental ABIEncoderV2;

import "./Token.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjects.sol";
import "./VerusSerializer.sol";

contract TokenManager {
    event TokenCreated(address tokenAddress);
    VerusSerializer verusSerializer;
    uint256 constant TICKER_LENGTH_MAX = 4;

    struct mappedToken {
        address erc20ContractAddress;
        uint8 flags;
        string name;
        string ticker;
        uint tokenIndex;
        address launchSystemID;
    }

    struct setupToken {
        address iaddress;
        address erc20ContractAddress;
        address launchSystemID;
        uint8 flags;
        string name;
        string ticker;
    }

    mapping(address => mappedToken) public verusToERC20mapping;
    address[] public tokenList;
    address verusBridgeContract;

    constructor(
        address verusSerializerAddress,
        setupToken[] memory tokensToLaunch
    ) {
        verusBridgeContract = address(0);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        launchTokens(tokensToLaunch);
    }

    function getTokenList() public view returns(setupToken[] memory ) {

        setupToken[] memory temp = new setupToken[](tokenList.length);

        for(uint i=0; i< tokenList.length; i++) {
            temp[i].iaddress = tokenList[i];
            temp[i].erc20ContractAddress = verusToERC20mapping[tokenList[i]].erc20ContractAddress;
            temp[i].name = verusToERC20mapping[tokenList[i]].name;
            temp[i].ticker = verusToERC20mapping[tokenList[i]].ticker;
            temp[i].flags = verusToERC20mapping[tokenList[i]].flags;
            temp[i].launchSystemID = verusToERC20mapping[tokenList[i]].launchSystemID;
        }

        return temp;
    }

    function convertFromVerusNumber(uint256 a, uint8 decimals)
        public
        pure
        returns (uint256)
    {
        uint8 power = 10; //default value for 18
        uint256 c = a;
        if (decimals > 8) {
            power = decimals - 8; // number of decimals in verus
            c = a * (10**power);
        } else if (decimals < 8) {
            power = 8 - decimals; // number of decimals in verus
            c = a / (10**power);
        }

        return c;
    }

    function setVerusBridgeContract(address _verusBridgeContract) public {
        require(
            verusBridgeContract == address(0),
            "verusBridgeContract Address has already been set."
        );
        verusBridgeContract = _verusBridgeContract;
    }

    function isVerusBridgeContract() private view returns (bool) {
        if (verusBridgeContract == address(0)) return true;
        else return msg.sender == verusBridgeContract;
    }

    //Tokens that are being exported from the eth blockchain are either destroyed or held until imported
    function exportERC20Tokens(address _iaddress, uint256 _tokenAmount) public {
        require(
            isVerusBridgeContract(),
            "Call can only be made from Verus Bridge Contract"
        );
        //check that the erc20 token is registered with the tokenManager
        require(verusToERC20mapping[_iaddress].erc20ContractAddress != address(0), "Token has not been registered yet");

        Token token = Token(verusToERC20mapping[_iaddress].erc20ContractAddress);

        //transfer the tokens to the contract address
        uint256 allowedTokens = token.allowance(msg.sender, address(this));
        require(
            allowedTokens >= _tokenAmount,              //values in wei
            "Not enough tokens have been approved"
        ); 
        //if its not approved it wont work
        token.transferFrom(msg.sender, address(this), _tokenAmount);

        if (verusToERC20mapping[_iaddress].flags & 
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
            isVerusBridgeContract(),
            "Call can only be made from Verus Bridge Contract"
        );
        address contractAddress;
        // if the token has not been previously created then it must be deployed

        // if token that has been sent from verus is not registered on ETH burn the tokens
        if (verusToERC20mapping[_iaddress].erc20ContractAddress != address(0)) {
            contractAddress = verusToERC20mapping[_iaddress]
                .erc20ContractAddress;

            Token token = Token(contractAddress);
            uint256 processedTokenAmount = convertFromVerusNumber(
                _tokenAmount,
                token.decimals()
            );
            //if the token has been created by this contract then burn the token
            if (verusToERC20mapping[_iaddress].flags & 
              VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) {

                token.mint(address(_destination), processedTokenAmount);

            } else {
                //transfer from the contract
                token.transfer(address(_destination), processedTokenAmount);
            }
        }
    }

    function ERC20Registered(address hosted) public view returns (bool) {

        return verusToERC20mapping[hosted].erc20ContractAddress != address(0);
        
    }

    function getTokenERC20(address VRSCAddress) public view returns (Token) {
        mappedToken memory internalToken = verusToERC20mapping[VRSCAddress];
        require(internalToken.erc20ContractAddress != address(0), "The token is not registered");
        Token token = Token(internalToken.erc20ContractAddress);
        return token;
    }

    function getSymbol(string memory _text)
        private
        pure
        returns (string memory)
    {
        bytes memory copy = new bytes(TICKER_LENGTH_MAX);
        bytes memory textAsBytes = bytes(_text);
        uint256 max = (
            textAsBytes.length > TICKER_LENGTH_MAX
                ? TICKER_LENGTH_MAX
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

        if(_ccd.parent == 0x0000000000000000000000000000000000000000) {
            return address(ripemd160(abi.encodePacked(sha256(abi.encodePacked(sha256d(_toLower(_ccd.name)))))));
        }
        else {
            return address(ripemd160(abi.encodePacked(sha256(abi.encodePacked(sha256d(abi.encodePacked(_ccd.parent,sha256d(_toLower(_ccd.name)))))))));
        }
    }

    function deployToken(bytes memory _serializedCcd) public returns (address) {
        
        require (isVerusBridgeContract(),"Call can only be made from Verus Bridge Contract");

        VerusObjects.CcurrencyDefinition memory ccd = verusSerializer
            .deSerializeCurrencyDefinition(_serializedCcd);
        address destinationCurrencyID = getIAddress(ccd);

        if (verusToERC20mapping[destinationCurrencyID].erc20ContractAddress != address(0))
            return verusToERC20mapping[destinationCurrencyID].erc20ContractAddress;

        uint8 currencyFlags;

        if (ccd.systemID != VerusConstants.VEth) 
            currencyFlags = VerusConstants.MAPPING_VERUS_OWNED;

        return recordToken(destinationCurrencyID, ccd.nativeCurrencyID, ccd.name, getSymbol(ccd.name), currencyFlags, ccd.launchSystemID);
    }

    // Called from constructor to launch pre-defined currencies.
    function launchTokens(setupToken[] memory tokensToDeploy) private {
        require (isVerusBridgeContract(),
            "Call can only be made from Verus Bridge Contract"
        );

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

        if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED ) {

            Token t = new Token(name, ticker);      
            verusToERC20mapping[_iaddress] = mappedToken(address(t), flags, name, ticker, tokenList.length, launchSystemID);
            tokenList.push(_iaddress); 
            emit TokenCreated(address(t));
            return address(t);

        } else {

            verusToERC20mapping[_iaddress] = mappedToken(ethContractAddress, flags, name, ticker, tokenList.length, launchSystemID);
            tokenList.push(_iaddress);
            return ethContractAddress;

        }
    }
}