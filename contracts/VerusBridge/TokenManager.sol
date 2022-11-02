// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.20;
pragma abicoder v2;

import "./Token.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjects.sol";
import "./VerusSerializer.sol";
import "../VerusBridge/VerusBridge.sol";

import "../VerusBridge/VerusBridgeStorage.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./VerusBridgeMaster.sol";

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
            temp[i].iaddress = iAddress;
            temp[i].flags = recordedToken.flags;

            if (iAddress == VerusConstants.VEth)
            {
                temp[i].erc20ContractAddress = address(0);
                temp[i].name = "Testnet ETH";
                temp[i].ticker = "ETH";
            }
            else if(recordedToken.flags & VerusConstants.TOKEN_LAUNCH == VerusConstants.TOKEN_LAUNCH )
            {
                Token token = Token(recordedToken.erc20ContractAddress);
                temp[i].erc20ContractAddress = address(token);
                temp[i].name = recordedToken.name;
                temp[i].ticker = token.symbol();
            }
            else if(recordedToken.flags & VerusConstants.TOKEN_ETH_NFT_DEFINITION == VerusConstants.TOKEN_ETH_NFT_DEFINITION)
            {
                temp[i].erc20ContractAddress = recordedToken.erc20ContractAddress;
                temp[i].name = recordedToken.name;
                temp[i].tokenID = recordedToken.tokenID;
            }
            
        }

        return temp;
    }
  
    function isVerusBridgeContract(address sender) private view returns (bool) {
       
       return (sender == upgradeManager.getBridgeAddress());

    }

    function ERC20Registered(address _iaddress) public view returns (bool) {

        return verusToERC20mapping(_iaddress).flags > 0;
        
    }

    function byteSlice(bytes memory _data) internal pure returns(bytes memory result) {
        
        uint256 length;
        length = _data.length;
        if (length > VerusConstants.TICKER_LENGTH_MAX) 
        {
            length = VerusConstants.TICKER_LENGTH_MAX;
        }
        result = new bytes(length);

        for (uint i = 0; i < length; i++) {
            result[i] = _data[i];
        }
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

    function getName(address cont) public view returns (string memory)
    {
        return ERC20(cont).name();
    }

    function getNFTName(address cont) public view returns (string memory)
    {
        return ERC721(cont).name();
    }

    function launchToken(VerusObjects.PackedCurrencyLaunch[] memory _tx) private {
        
        for (uint j = 0; j < _tx.length; j++)
        {
            if (ERC20Registered(_tx[j].iaddress) || _tx[j].iaddress == address(0))
                continue;

            uint8 nameLen;
            nameLen = uint8(_tx[j].nameAndFlags & 0xff);
            bytes memory name = new bytes(nameLen);
            string memory outputName;

            for (uint i = 0; i< nameLen;i++)
            {
                name[i] = bytes1(uint8(_tx[j].nameAndFlags >> ((i+1) * 8)));
            }

            //TODO: decide here whether, A) token ETH mapped using native B) verus token minted to new ERC20, c)NFT eth mapped d) NFT minted from tokenized ID.

            if (uint8(_tx[j].nameAndFlags >> 160) == VerusConstants.MAPPING_ETHEREUM_OWNED + VerusConstants.TOKEN_LAUNCH)
            {
                try (this).getName(_tx[j].ERCContract) returns (string memory retval) 
                {
                    outputName = string(abi.encodePacked("[", retval, "] as ", name));
                } 
                catch 
                {
                    continue;
                }
            }
            else if (uint8(_tx[j].nameAndFlags >> 160) == VerusConstants.MAPPING_ETHEREUM_OWNED + VerusConstants.TOKEN_ETH_NFT_DEFINITION)
            {
                try (this).getNFTName(_tx[j].ERCContract) returns (string memory retval) 
                {
                    outputName = string(abi.encodePacked("[", retval, "] as ", name));
                } 
                catch 
                {
                    continue;
                }     
            } 
            else 
            {
                outputName = string(name);
            }

            recordToken(_tx[j].iaddress, _tx[j].ERCContract, outputName, string(byteSlice(bytes(name))), uint8(_tx[j].nameAndFlags >> 160), _tx[j].tokenID);
        }
    }

    function launchContractTokens(VerusObjects.setupToken[] memory tokensToDeploy) public  {

        require(verusBridgeStorage.getERCMapping(VerusConstants.VEth).erc20ContractAddress == address(0), "Launch tokens already set");

        for (uint256 i = 0; i < tokensToDeploy.length; i++) {
            recordToken(
                tokensToDeploy[i].iaddress,
                tokensToDeploy[i].erc20ContractAddress,
                tokensToDeploy[i].name,
                tokensToDeploy[i].ticker,
                tokensToDeploy[i].flags,
                uint256(0)

            );
        }
    }

    function recordToken(
        address _iaddress,
        address ethContractAddress,
        string memory name,
        string memory ticker,
        uint8 flags,
        uint256 tokenID
    ) private returns (address) {

        address ERCContract;

        if (flags & VerusConstants.TOKEN_LAUNCH == VerusConstants.TOKEN_LAUNCH) 
        {
            if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) 
            {
                ERCContract = verusBridgeStorage.emitNewToken(name, ticker);      
            } 
            else 
            {
                ERCContract = ethContractAddress;
            }
            
        } 
        else if (flags & VerusConstants.TOKEN_ETH_NFT_DEFINITION == VerusConstants.TOKEN_ETH_NFT_DEFINITION) 
        {
            if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) 
            {
                ///TODO: call mint NFT contract
                // ERCContract == NFTcontract;
            }
            ERCContract = ethContractAddress;
        }
        
        verusBridgeStorage.RecordTokenmapping(_iaddress, VerusObjects.mappedToken(ERCContract, flags, verusBridgeStorage.getTokenListLength(), name, tokenID));
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

    function processTransactions(bytes calldata serializedTransfers, uint8 numberOfTransfers) 
                public returns (VerusObjects.ETHPayments[] memory)
    {
        require(msg.sender == verusBridge,"proctx's:vb_only" );
        VerusObjects.PackedSend[] memory transfers;
        VerusObjects.PackedCurrencyLaunch[] memory launchTxs;
        uint32 counter;
        (transfers, launchTxs, counter) = verusSerializer.deserializeTransfers(serializedTransfers, numberOfTransfers);

        // counter: 16bit packed 32bit number for efficency
        uint8 ETHPaymentCounter = uint8((counter >> 16) & 0xff);
        uint8 currencyCounter = uint8((counter >> 24) & 0xff);
        uint8 transferCounter = uint8((counter & 0xff) - ETHPaymentCounter);

        VerusObjects.ETHPayments[] memory payments;

        if(ETHPaymentCounter > 0 )
            payments = new VerusObjects.ETHPayments[](ETHPaymentCounter); //Avoid empty

        ETHPaymentCounter = 0;
        for (uint8 i = 0; i< transfers.length; i++) {

            uint8 flags = uint8((transfers[i].destinationAndFlags >> 160));
            
            // Handle ETH Send
            if (flags & VerusConstants.TOKEN_ETH_SEND == VerusConstants.TOKEN_ETH_SEND) 
            {
                // ETH is held in VerusBridgemaster, create array to bundle payments
                payments[ETHPaymentCounter] = VerusObjects.ETHPayments(
                    address(uint160(transfers[i].destinationAndFlags)), 
                    (transfers[i].currencyAndAmount >> 160) * VerusConstants.SATS_TO_WEI_STD); //SATS to WEI (only for ETH)
                ETHPaymentCounter++;                      
            }               
        }

        if (transferCounter > 0)
            verusBridgeStorage.importTransactions(transfers);

        if (currencyCounter > 0)
        {
            launchToken(launchTxs);
        }

        //return ETH and addresses to be sent to + total payments
        return payments;

    }
}