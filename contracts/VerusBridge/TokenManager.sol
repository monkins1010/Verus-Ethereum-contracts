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

    //array of contracts address mapped to the token name
    struct hostedToken {
        address erc20ContractAddress;
        bool VerusOwned;
        bool isRegistered;
    }

    struct deployTokens {
        address iaddress;
        address eth_contract;
        bool mapped;
        string name;
        string ticker;
    }

    mapping(address => hostedToken) public verusToERC20mapping;
    deployTokens[] public tokenList;
    address verusBridgeContract;

    constructor(
        address verusSerializerAddress,
        deployTokens[] memory tokensToLaunch
    ) {
        verusBridgeContract = address(0);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        launchTokens(tokensToLaunch);
    }

    function getTokenList() public view returns(deployTokens[] memory ) {

        deployTokens[] memory temp = new deployTokens[](tokenList.length);

        for(uint i=0; i< tokenList.length; i++)
            temp[i] = tokenList[i];

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
        require(verusToERC20mapping[_iaddress].isRegistered, "Token has not been registered yet");

        Token token = Token(verusToERC20mapping[_iaddress].erc20ContractAddress);

        //transfer the tokens to the contract address
        uint256 allowedTokens = token.allowance(msg.sender, address(this));
        require(
            allowedTokens >= _tokenAmount,              //values in wei
            "Not enough tokens have been approved"
        ); 
        //if its not approved it wont work
        token.transferFrom(msg.sender, address(this), _tokenAmount);

        if (verusToERC20mapping[_iaddress].VerusOwned) {

            require(token.balanceOf(address(this)) >= _tokenAmount,
                "Tokens didnt transfer"
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
        if (verusToERC20mapping[_iaddress].isRegistered) {
            contractAddress = verusToERC20mapping[_iaddress]
                .erc20ContractAddress;

            Token token = Token(contractAddress);
            uint256 processedTokenAmount = convertFromVerusNumber(
                _tokenAmount,
                token.decimals()
            );
            //if the token has been created by this contract then burn the token
            if (verusToERC20mapping[_iaddress].VerusOwned) {

                token.mint(address(_destination), processedTokenAmount);

            } else {
                //transfer from the contract
                token.transfer(address(_destination), processedTokenAmount);
            }
        }
    }

    function getTokenERC20(address VRSCAddress) public view returns (Token) {
        hostedToken memory internalToken = verusToERC20mapping[VRSCAddress];
        require(internalToken.isRegistered, "The token is not registered");
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
        
        require(isVerusBridgeContract(),"Call can only be made from Verus Bridge Contract");

        VerusObjects.CcurrencyDefinition memory ccd = verusSerializer
            .deSerializeCurrencyDefinition(_serializedCcd);
        address destinationCurrencyID = getIAddress(ccd);

        if (verusToERC20mapping[destinationCurrencyID].isRegistered)
            return
                verusToERC20mapping[destinationCurrencyID].erc20ContractAddress;

        if (ccd.systemID != VerusConstants.VEth) {
            //we are minting a new ERC20 token

            return
                recordCreatedToken(
                    destinationCurrencyID,
                    ccd.name,
                    getSymbol(ccd.name)
                );
        } else {
            // we are adding an existing token to the list

            recordMappedToken(destinationCurrencyID, ccd.nativeCurrencyID);
            // destinationToAddress[destinationCurrencyID] = ccd.nativeCurrencyID;
            return ccd.nativeCurrencyID;
        }
    }

    // Called from constructor to launch pre-defined currencies.
    function launchTokens(deployTokens[] memory tokensToDeploy) private {
        require(
            isVerusBridgeContract(),
            "Call can only be made from Verus Bridge Contract"
        );

        for (uint256 i = 0; i < tokensToDeploy.length; i++) {
            if (tokensToDeploy[i].mapped) {
                recordMappedToken(
                    tokensToDeploy[i].iaddress,
                    tokensToDeploy[i].eth_contract
                );
                // destinationToAddress[tokensToDeploy[i].verusID] = tokensToDeploy[i].eth_contract;
            } else {
                recordCreatedToken(
                    tokensToDeploy[i].iaddress,
                    tokensToDeploy[i].name,
                    tokensToDeploy[i].ticker
                );
            }
        }
    }

    function recordMappedToken(address _iaddress, address ethContractAddress)
        private
        returns (address)
    {
        verusToERC20mapping[_iaddress] = hostedToken(
            address(ethContractAddress),
            false,
            true
        );
        Token token = Token(ethContractAddress);
        tokenList.push(deployTokens(_iaddress, ethContractAddress, true, token.name(), token.symbol()));
        return _iaddress;
    }

    function recordCreatedToken(
        address _iaddress,
        string memory name,
        string memory ticker
    ) private returns (address) {
        Token t = new Token(name, ticker);
        verusToERC20mapping[_iaddress] = hostedToken(address(t), true, true);
        tokenList.push(deployTokens(_iaddress, address(t), false, name, ticker));
        emit TokenCreated(address(t));
        return address(t);
    }

}
