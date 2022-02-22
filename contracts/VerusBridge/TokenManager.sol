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
    struct hostedToken{
        address destinationCurrencyID;
        bool VerusOwned;
        bool isRegistered;
    }

    struct deployTokens{
        address verusID;
        address eth_contract;
        string name;
        string ticker;
        bool mapped;
    }
    
    mapping(address => hostedToken) public verusToERC20mapping;
    mapping(address => address) public destinationToAddress;
    mapping(address => hostedToken) public vERC20Tokens;
    
    address verusBridgeContract;
    
    constructor(address verusSerializerAddress, deployTokens[] memory tokensToLaunch) {
        verusBridgeContract = address(0);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        launchTokens(tokensToLaunch);
    }

    function convertFromVerusNumber(uint256 a, uint8 decimals) public pure returns (uint256) {
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
    
    function setVerusBridgeContract(address _verusBridgeContract) public {
        require(verusBridgeContract == address(0),"verusBridgeContract Address has already been set.");
        verusBridgeContract = _verusBridgeContract;
    }
    
    function isVerusBridgeContract() private view returns(bool){
        if(verusBridgeContract == address(0)) return true;
        else return msg.sender == verusBridgeContract;
    }
    
    //Tokens that are being exported from the eth blockchain are either destroyed or held until imported
    function exportERC20Tokens(address _contractAddress, uint256 _tokenAmount) public {
        require(isVerusBridgeContract(),"Call can only be made from Verus Bridge Contract");
        //check that the erc20 token is registered with the tokenManager
        require(isToken(_contractAddress),"Token has not been registered yet");
        
        Token token = Token(_contractAddress);
        hostedToken memory tokenDetail;
        //transfer the tokens to the contract address
        uint256 allowedTokens = token.allowance(msg.sender,address(this));
        require( allowedTokens >= _tokenAmount,"Not enough tokens have been approved"); //values in wei
        //if its not approved it wont work
        token.transferFrom(msg.sender,address(this),_tokenAmount);   
        
        if(!isToken(_contractAddress)) {
            tokenDetail = vERC20Tokens[_contractAddress];
            //if the token has been cerated by this contract then burn the token
        }

        if (tokenDetail.VerusOwned){
            require(token.balanceOf(address(this)) >= _tokenAmount,"Tokens didnt transfer");
            burnToken(_contractAddress,_tokenAmount);
        } else {
            //the contract stores the token
        }
    }

    function importERC20Tokens(address _destCurrencyID,uint64 _tokenAmount,address _destination) public {
        require(isVerusBridgeContract(),"Call can only be made from Verus Bridge Contract");
        address contractAddress;
        // if the token has not been previously created then it must be deployed
    
        // if token that has been sent from verus is not registered on ETH burn the tokens
        if (verusToERC20mapping[_destCurrencyID].isRegistered) {
               
            contractAddress = destinationToAddress[_destCurrencyID];
            
            hostedToken memory tokenDetail = vERC20Tokens[contractAddress];
            Token token = Token(contractAddress);
            uint256 processedTokenAmount = convertFromVerusNumber(_tokenAmount, token.decimals());
            //if the token has been created by this contract then burn the token
            if(tokenDetail.VerusOwned){
                mintToken(contractAddress,processedTokenAmount,address(_destination));
            } else {
                //transfer from the contract
                token.transfer(address(_destination),processedTokenAmount);   
            }
        }

    }

    function balanceOf(address _contractAddress,address _account) public view returns(uint256){
        Token token = Token(_contractAddress);
        return token.balanceOf(_account);
    }
    function allowance(address _contractAddress,address _owner, address _spender) public view returns(uint256){
        Token token = Token(_contractAddress);
        return token.allowance(_owner,_spender);
    }

    function mintToken(address _contractAddress,uint256 _mintAmount,address _recipient) private {
        Token token = Token(_contractAddress);
        token.mint(_recipient,_mintAmount);
    }

    function burnToken(address _contractAddress,uint _burnAmount) private {
        Token token = Token(_contractAddress);
        token.burn(_burnAmount);
    }

 /*   function addExistingToken(address _ERC20contractAddress,address _verusAddress) public returns(address){
        require(!isToken( _verusAddress),"Token is already registered");
        //generate a address for the token name
        //Token token = Token( _ERC20contractAddress);
        verusToERC20mapping[_verusAddress] = hostedToken(address(_ERC20contractAddress),false,true);
        vERC20Tokens[ _ERC20contractAddress] = hostedToken(_verusAddress,false,true);
        destinationToAddress[_verusAddress] = _ERC20contractAddress;
        return _verusAddress;
    } */

    function getTokenERC20(address VRSCAddress) public view returns(Token){
        hostedToken memory internalToken = verusToERC20mapping[VRSCAddress];
        require(internalToken.isRegistered, "The token is not registered");
        Token token = Token(internalToken.destinationCurrencyID);
        return token;
    }

    function getSymbol(string memory _text) public pure returns (string memory)
    {
        bytes memory copy = new bytes(TICKER_LENGTH_MAX);
        bytes memory textAsBytes = bytes(_text);
        uint256 max = (textAsBytes.length > TICKER_LENGTH_MAX ? TICKER_LENGTH_MAX : uint8(textAsBytes.length)) + 31;
        for (uint256 i=32; i<=max; i+=32)
        {
            assembly { mstore(add(copy, i), mload(add(textAsBytes, i))) }
        }
        return string(copy);
    }

    function sha256d(bytes32 _bytes) internal pure returns(bytes32){
        return sha256(abi.encodePacked(sha256(abi.encodePacked(_bytes))));
    }

    function sha256d(string memory _string) internal pure returns(bytes32){
        return sha256(abi.encodePacked(sha256(abi.encodePacked(_string))));
    }

    function sha256d(bytes memory _bytes) internal pure returns(bytes32){
        return sha256(abi.encodePacked(sha256(abi.encodePacked(_bytes))));
    }

    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        for (uint i = 0; i < bStr.length; i++) {
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
        // TODO: require(isVerusBridgeContract(),"Call can only be made from Verus Bridge Contract");
        
        VerusObjects.CcurrencyDefinition memory ccd = verusSerializer.deSerializeCurrencyDefinition(_serializedCcd);
        address destinationCurrencyID = getIAddress(ccd);

        if(verusToERC20mapping[destinationCurrencyID].isRegistered) 
            return verusToERC20mapping[destinationCurrencyID].destinationCurrencyID;

        if(ccd.systemID != VerusConstants.VEth) { //we are minting a new ERC20 token
            
            Token t = new Token(ccd.name, getSymbol(ccd.name));
            verusToERC20mapping[destinationCurrencyID] = hostedToken(address(t),true,true); 
            vERC20Tokens[address(t)]= hostedToken(destinationCurrencyID,true,true);
            destinationToAddress[destinationCurrencyID] = address(t);
            emit TokenCreated(address(t));
            return address(t);

        } else { // we are adding an existing token to the list

            verusToERC20mapping[destinationCurrencyID] = hostedToken(address(ccd.nativeCurrencyID),false,true);
            vERC20Tokens[ccd.nativeCurrencyID] = hostedToken(destinationCurrencyID,false,true);
            destinationToAddress[destinationCurrencyID] = ccd.nativeCurrencyID;
            return ccd.nativeCurrencyID;
        }
    }

    // Called from constructor to launch pre-defined currencies.
    function launchTokens(deployTokens[] memory tokensToDeploy) private {
        
        require(isVerusBridgeContract(),"Call can only be made from Verus Bridge Contract");
        
        for(uint i=0; i < tokensToDeploy.length ; i++) {

            if(tokensToDeploy[i].mapped) {

                //TODO: Duplicate code of above make into a function
                verusToERC20mapping[tokensToDeploy[i].verusID] = hostedToken(address(tokensToDeploy[i].eth_contract),false,true);
                vERC20Tokens[tokensToDeploy[i].eth_contract] = hostedToken(tokensToDeploy[i].verusID,false,true);
                destinationToAddress[tokensToDeploy[i].verusID] = tokensToDeploy[i].eth_contract;

            } else {

                Token t = new Token(tokensToDeploy[i].name, tokensToDeploy[i].ticker);
                verusToERC20mapping[tokensToDeploy[i].verusID] = hostedToken(address(t),true,true); 
                vERC20Tokens[address(t)]= hostedToken(tokensToDeploy[i].verusID,true,true);
                destinationToAddress[tokensToDeploy[i].verusID] = address(t);
                emit TokenCreated(address(t));

            }
        }
 
    }

    function isToken(address _contractAddress) public view returns(bool){
        return vERC20Tokens[_contractAddress].isRegistered;
    }

    function isVerusOwned(address _contractAddress) public view returns(bool){
        return vERC20Tokens[_contractAddress].VerusOwned;
    }

}