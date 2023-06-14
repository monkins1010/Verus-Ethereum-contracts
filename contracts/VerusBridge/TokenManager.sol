// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.20;
pragma abicoder v2;

import "./Token.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjects.sol";
import {VerusSerializer} from "../VerusBridge/VerusSerializer.sol";
import "../VerusBridge/CreateExports.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../Storage/StorageMaster.sol";


contract TokenManager is VerusStorage {

    function getName(address cont) public view returns (string memory)
    {
        // Wrapper functions to enable try catch to work
        (bool success, bytes memory result) = address(cont).staticcall(abi.encodeWithSignature("name()"));
        if (success) {
            return abi.decode(result, (string));
        } else {
            return "";
        }
    }

    function launchToken(VerusObjects.PackedCurrencyLaunch[] memory _tx) private {
        
        for (uint j = 0; j < _tx.length; j++)
        {
            // If the iaddress is already mapped or the iaddress is null skip token register
            if (verusToERC20mapping[_tx[j].iaddress].flags > 0 || _tx[j].iaddress == address(0))
                continue;

            string memory outputName;

            if ((uint8(_tx[j].flags) & VerusConstants.MAPPING_ETHEREUM_OWNED) == VerusConstants.MAPPING_ETHEREUM_OWNED)
            {
                outputName = getName(_tx[j].ERCContract);
                if (bytes(outputName).length == 0) 
                {
                    continue;
                }
                outputName = string(abi.encodePacked("[", outputName, "] as ", _tx[j].name));
            }
            else if (_tx[j].parent != VerusConstants.VerusSystemId)
            {
                outputName = string(abi.encodePacked(_tx[j].name, ".", verusToERC20mapping[_tx[j].parent].name));
            }
            else
            {
                outputName = _tx[j].name;
            }
            recordToken(_tx[j].iaddress, _tx[j].ERCContract, outputName, string(byteSlice(bytes(_tx[j].name))), uint8(_tx[j].flags), _tx[j].tokenID);
        }
    }

    
    function launchContractTokens(bytes calldata data) external {

        VerusObjects.setupToken[] memory tokensToDeploy = abi.decode(data, (VerusObjects.setupToken[]));

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

        if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) 
        {
            if (flags & VerusConstants.TOKEN_LAUNCH == VerusConstants.TOKEN_LAUNCH) 
            {
                Token t = new Token(name, ticker); 
                ERCContract = address(t); 
            }
            else if (flags & VerusConstants.TOKEN_ETH_NFT_DEFINITION == VerusConstants.TOKEN_ETH_NFT_DEFINITION)
            {
                ERCContract = verusToERC20mapping[VerusConstants.VerusNFTID].erc20ContractAddress;
                tokenID = uint256(uint160(_iaddress)); //tokenID is the i address
            }
        }
        else 
        {
            ERCContract = ethContractAddress;
        }

        tokenList.push(_iaddress);
        verusToERC20mapping[_iaddress] = VerusObjects.mappedToken(ERCContract, flags, tokenList.length, name, tokenID);
    
        return ERCContract;
    }

    function processTransactions(bytes calldata serializedTransfers, uint8 numberOfTransfers) 
                external returns (bytes memory refundsData)
    {

        VerusObjects.PackedSend[] memory transfers;
        VerusObjects.PackedCurrencyLaunch[] memory launchTxs;
        uint176[] memory refundAddresses;
        uint32 counter;
        (transfers, launchTxs, counter, refundAddresses) = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).deserializeTransfers(serializedTransfers, numberOfTransfers);

        refundsData = importTransactions(transfers, refundAddresses);

        if (uint8(counter >> 24) > 0) {
            launchToken(launchTxs);
        }

        //return ETH and addresses to be sent ETH to + payment details
        return (refundsData);
    }

    function importTransactions(VerusObjects.PackedSend[] memory trans, uint176[] memory refundAddresses) private returns (bytes memory refundsData){
      
        uint32 sendFlags;
        Token token;

        for(uint256 i = 0; i < trans.length; i++)
        {
            VerusObjects.mappedToken memory tempToken = verusToERC20mapping[address(uint160(trans[i].currencyAndAmount))];
            address destinationAddress;
            destinationAddress  = address(uint160(trans[i].destinationAndFlags));
            sendFlags = uint32(trans[i].destinationAndFlags >> VerusConstants.UINT160_BITS_SIZE);
            
            if (sendFlags & VerusConstants.TOKEN_ETH_SEND == VerusConstants.TOKEN_ETH_SEND) 
            {
                if (!payable(destinationAddress).send((trans[i].currencyAndAmount >> VerusConstants.UINT160_BITS_SIZE) * VerusConstants.SATS_TO_WEI_STD)) {
                    // Note: Refund address is a CTransferdestination and Amount is in VerusSATS, so store as that.
                    refundsData = abi.encodePacked(refundsData, bytes32(uint256(refundAddresses[i])), uint64((trans[i].currencyAndAmount >> VerusConstants.UINT160_BITS_SIZE)));
                }              
            }   
            else if (sendFlags & VerusConstants.TOKEN_ERC20_SEND == VerusConstants.TOKEN_ERC20_SEND  &&
                   tempToken.flags & VerusConstants.TOKEN_LAUNCH == VerusConstants.TOKEN_LAUNCH )
            {
                token = Token(tempToken.erc20ContractAddress);
                
                if (destinationAddress != address(0))
                {
                    bool shouldMint = (tempToken.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED);
                     
                    mintOrTransferToken(token, destinationAddress, 
                            convertFromVerusNumber(uint256(trans[i].currencyAndAmount >> VerusConstants.UINT160_BITS_SIZE), token.decimals()), shouldMint);
                }
            } 
            else if (tempToken.flags & VerusConstants.TOKEN_ETH_NFT_DEFINITION == VerusConstants.TOKEN_ETH_NFT_DEFINITION &&
                   tempToken.flags & VerusConstants.MAPPING_ETHEREUM_OWNED == VerusConstants.MAPPING_ETHEREUM_OWNED )
            {
                if (destinationAddress != address(0))
                {
                    ERC721(tempToken.erc20ContractAddress).transferFrom(address(this), destinationAddress, tempToken.tokenID);
                }
            }
            else if (tempToken.flags & VerusConstants.TOKEN_ETH_NFT_DEFINITION == VerusConstants.TOKEN_ETH_NFT_DEFINITION &&
                   tempToken.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED )
            {

                if (destinationAddress != address(0))
                {
                    VerusNft t = VerusNft(verusToERC20mapping[address(uint160(trans[i].currencyAndAmount))].erc20ContractAddress);
                    t.mint(address(uint160(trans[i].currencyAndAmount)), tempToken.name, destinationAddress);
                }
            }
        } 
    }

    function mintOrTransferToken(Token token, address destinationAddress, uint256 amount, bool mint ) private {

            if (mint) 
            {   
                token.mint(destinationAddress, amount);
            } 
            else 
            {
                (bool success, ) = address(token).call(abi.encodeWithSignature("transfer(address,uint256)", destinationAddress, amount));
                require(success);
            }
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
    function convertFromVerusNumber(uint256 a,uint8 decimals) internal pure returns (uint256) {
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