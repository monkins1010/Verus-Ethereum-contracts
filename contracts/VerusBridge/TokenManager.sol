// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.20;
pragma experimental ABIEncoderV2;

import "./Token.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjects.sol";
import "./VerusSerializer.sol";
import "../VerusBridge/VerusBridge.sol";

import "../VerusBridge/VerusBridgeStorage.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TokenManager {

    VerusSerializer verusSerializer;
    VerusBridgeStorage verusBridgeStorage;
    UpgradeManager upgradeManager;
    address verusBridge;

    constructor(
        address verusUpgradeAddress,
        address verusBridgeStorageAddress,
        address verusSerializerAddress
    ) {
        
        verusBridgeStorage = VerusBridgeStorage(verusBridgeStorageAddress); 
        verusSerializer = VerusSerializer(verusSerializerAddress);
        upgradeManager = UpgradeManager(verusUpgradeAddress);
        
    }
    
    function setContracts(address serializerAddress, address verusBridgeAddress) public {

        require(msg.sender == address(upgradeManager));

        if(serializerAddress != address(verusSerializer))
            verusSerializer = VerusSerializer(serializerAddress);
        if(verusBridgeAddress != verusBridge)
            verusBridge = verusBridgeAddress;
    }

    function verusToERC20mapping(address iaddress) public view returns (VerusObjects.mappedToken memory) {

        return verusBridgeStorage.getERCMapping(iaddress);
      
    }

    function getTokenList() public view returns(VerusObjects.setupToken[] memory ) {

        uint tokenListLength;
        tokenListLength = verusBridgeStorage.getTokenListLength();
        VerusObjects.setupToken[] memory temp = new VerusObjects.setupToken[](tokenListLength);
        VerusObjects.mappedToken memory recordedToken;

        for(uint i=0; i< tokenListLength; i++) {

            address iAddress;
            iAddress = verusBridgeStorage.tokenList(i);
            recordedToken = verusBridgeStorage.getERCMapping(iAddress);

            if(iAddress != VerusConstants.VEth )
            {
                Token token = Token(recordedToken.erc20ContractAddress);
                temp[i].erc20ContractAddress = address(token);
                temp[i].name = recordedToken.name;
                temp[i].ticker = token.symbol();
            }
            else
            {
                temp[i].erc20ContractAddress = address(0);
                temp[i].name = "Testnet ETH";
                temp[i].ticker = "ETH";
            }
            temp[i].iaddress = iAddress;
            temp[i].flags = recordedToken.flags;
        }

        return temp;
    }
  
    function isVerusBridgeContract(address sender) private view returns (bool) {
       
       return (sender == upgradeManager.getBridgeAddress());

    }

    function ERC20Registered(address _iaddress) public view returns (bool) {

        return verusToERC20mapping(_iaddress).flags > 0;
        
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

    function getName(address cont) public view returns (string memory)
    {
        return ERC20(cont).name();
    }

    function deployToken(VerusObjects.PackedSend memory _tx) private {
        
        address destinationCurrencyID = address(uint160(_tx.currencyAndAmount));

        if (ERC20Registered(destinationCurrencyID))
            return;

        uint8 nameLen;
        nameLen = uint8(_tx.destinationAndFlags & 0xff);
        bytes memory name = new bytes(nameLen);
        string memory outputName;

        for (uint i = 0; i< nameLen;i++)
        {
            name[i] = bytes1(uint8(_tx.destinationAndFlags >> ((i+1) * 8)));
        }

        uint8 currencyFlags;

        if (_tx.nativeCurrency != address(0))
        {
            address erc20address = _tx.nativeCurrency;
            currencyFlags = VerusConstants.MAPPING_ETHEREUM_OWNED;

            try (this).getName(erc20address) returns (string memory retval) 
            {
                outputName = string(abi.encodePacked("[", retval, "] as ", name));
            } 
            catch 
            {
                return;
            }
        }
        else 
        {
            currencyFlags = VerusConstants.MAPPING_VERUS_OWNED;
            outputName = string(name);
        }

        recordToken(destinationCurrencyID, _tx.nativeCurrency, outputName, getSymbol(string(name)), currencyFlags);
    }

    function launchTokens(VerusObjects.setupToken[] memory tokensToDeploy) public  {

        require(verusBridgeStorage.getERCMapping(VerusConstants.VEth).erc20ContractAddress == address(0), "Launch tokens already set");

        for (uint256 i = 0; i < tokensToDeploy.length; i++) {
            recordToken(
                tokensToDeploy[i].iaddress,
                tokensToDeploy[i].erc20ContractAddress,
                tokensToDeploy[i].name,
                tokensToDeploy[i].ticker,
                tokensToDeploy[i].flags

            );
        }
    }

    function recordToken(
        address _iaddress,
        address ethContractAddress,
        string memory name,
        string memory ticker,
        uint8 flags
    ) private returns (address) {

        address ERCContract;

        if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED ) {

            ERCContract = verusBridgeStorage.emitNewToken(name, ticker, _iaddress);     

        } else {

            ERCContract = ethContractAddress;
            verusBridgeStorage.pushTokenList(_iaddress);

        }
        
        verusBridgeStorage.RecordverusToERC20mapping(_iaddress, VerusObjects.mappedToken(ERCContract, flags, verusBridgeStorage.getTokenListLength(), name));
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

    function processTransactions(VerusObjects.DeserializedObject memory transfers) 
                public returns (VerusObjects.ETHPayments[] memory)
    {
        
        require(msg.sender == verusBridge,"proctx's:vb_only");
        // counter: 16bit packed 32bit number for efficency
        uint8 ETHPaymentCounter = uint8((transfers.counter >> 16) & 0xff);
        uint8 currencyCounter = uint8((transfers.counter >> 24) & 0xff);
        uint8 transferCounter = uint8((transfers.counter & 0xff) - currencyCounter - ETHPaymentCounter);

        uint8[] memory transferLocations = new uint8[](transferCounter); 
        VerusObjects.ETHPayments[] memory payments;

        if(ETHPaymentCounter > 0 )
            payments = new VerusObjects.ETHPayments[](ETHPaymentCounter); //Avoid empty

        uint8[] memory currencyLocations;
        
        if(currencyCounter > 0 ) 
            currencyLocations = new uint8[](currencyCounter);

        currencyCounter = 0;
        ETHPaymentCounter = 0;
        transferCounter = 0;
        for (uint8 i = 0; i< transfers.transfers.length; i++) {

            uint8 flags = uint8((transfers.transfers[i].destinationAndFlags >> 160) & 0xff);
            
            // Handle ETH Send
            if (flags & VerusConstants.TOKEN_ETH_SEND == VerusConstants.TOKEN_ETH_SEND) 
            {
                uint256 amount; 
                amount = (transfers.transfers[i].currencyAndAmount >> 160) * VerusConstants.SATS_TO_WEI_STD;//SATS to WEI (only for ETH)
                // ETH is held in VerusBridgemaster, create array to bundle payments
                payments[ETHPaymentCounter] = VerusObjects.ETHPayments(
                    address(uint160(transfers.transfers[i].destinationAndFlags)), amount);
                ETHPaymentCounter++;                        
        
            } 
            else if(flags & VerusConstants.TOKEN_SEND == VerusConstants.TOKEN_SEND)
            { 
                transferLocations[transferCounter] = i;
                transferCounter++;
                
            } 
            else if (flags & VerusConstants.TOKEN_LAUNCH == VerusConstants.TOKEN_LAUNCH) 
            {                     
                currencyLocations[currencyCounter] = i;
                currencyCounter++;            
            }
            else
            {
                //REMOVE: comments and make NFT WORK
                //   uint256 NFTID; 
                //   ERC721 NFT;    
                //   if(NFTID != uint256(0))
                //       verusBridgeStorage.transferFromERC721(destinationAddress, address(verusBridgeStorage), NFT, NFTID );
            }
                
        }

        //send tokens
        if(transferCounter > 0)
            verusBridgeStorage.importTransactions(transfers.transfers, transferLocations);

        for(uint i = 0; i < currencyCounter; i++)
        {
            deployToken(transfers.transfers[currencyLocations[i]]);
        }

        uint256 totalPayments;
        if(ETHPaymentCounter > 0)
        {
            for(uint i = 0; i < ETHPaymentCounter; i++)
            {
                totalPayments += payments[i].amount;
            }
            
            verusBridgeStorage.subtractFromEthHeld(totalPayments);
        }
        //return ETH and addresses to be sent to 
        return payments;

    }
}