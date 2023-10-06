// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

import "./Token.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjects.sol";
import {VerusSerializer} from "../VerusBridge/VerusSerializer.sol";
import "../VerusBridge/CreateExports.sol";
import "../VerusBridge/UpgradeManager.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../Storage/StorageMaster.sol";
import "./VerusCrossChainExport.sol";

interface callGetName {
    function getName(address cont) external view returns(string memory);
}

contract TokenManager is VerusStorage {

    address immutable VETH;
    address immutable VERUS;
    address immutable DAIERC20ADDRESS;

    enum SendTypes {NULL, ETH, ERC20, ERC20MINT ,ERC721, ERC1155}

    uint8 constant SEND_FAILED = 1;
    uint8 constant SEND_SUCCESS = 2;
    uint8 constant SEND_SUCCESS_ERC1155 = 3;
    uint8 constant SEND_SUCCESS_ERC721 = 4;
    uint8 constant SEND_SUCCESS_ERC20_MINTED = 5;
    uint8 constant SEND_SUCCESS_ETH = 6;

    constructor(address vETH, address, address Verus, address DaiERC20Address){

        VETH = vETH;
        VERUS = Verus;
        DAIERC20ADDRESS = DaiERC20Address;
    }

    function getName(address cont) external returns (string memory ret)
    {
        // Wrapper functions to enable try catch to work
        bytes4 sig = 0x06FDDE03; //signature of function to call `name()`
        bytes32 c;
        uint8 tmp;
        ret = new string(32);
        assembly {
            let x := mload(0x40)   //Find empty storage location using "free memory pointer"
            let i := 0
            mstore(x,sig) //Place signature at begining of empty storage 

            if iszero(call(     
                            5000, //5k gas
                            cont, //To addr
                            0,    //No value
                            x,    //Inputs are stored at location x
                            0x20, //Inputs are 68 bytes long
                            x,    //Store output over input (saves space)
                            0x60)) {  //Outputs are 32 bytes long   
                revert(0, 0)
            }

            c := mload(x) //Assign output value to c
            switch c //0x06FDDE03
            case 0x06FDDE0300000000000000000000000000000000000000000000000000000000 {  
              revert(0, 0)
            }
            case 0 {  
              revert(0, 0)
            }
            case 0x20 { 
              // Store the string in the return variable 
              mstore(ret, mload(add(x,0x20)))
              mstore(add(ret,32), mload(add(x,0x40)))
            }
            default {
                // string stored in bytes32 so process one byte at a time until null terminator
                for {} iszero(0) {} {
                tmp := and(shr(sub(248,mul(i,8)),c), 0xff) 
                if iszero(tmp) {
                    break
                }
                mstore8(add(ret,add(i,32)), tmp)
                i := add(i, 1)
            }
            mstore(ret, i)

            }

        }
        return ret;
    }

    function launchToken(VerusObjects.PackedCurrencyLaunch[] memory _tx) private {
        
        for (uint j = 0; j < _tx.length; j++)
        {
            // If the iaddress is already mapped or the iaddress is null skip token register
            if (verusToERC20mapping[_tx[j].iaddress].flags > 0 || _tx[j].iaddress == address(0))
                continue;

            VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).checkIAddress(_tx[j]); 

            string memory outputName;

            // Only adjust the name of the token if it is a Ethereum owned token and it not a ERC1155 NFT
            if (_tx[j].flags & 
                (VerusConstants.MAPPING_ETHEREUM_OWNED | VerusConstants.MAPPING_ERC1155_ERC_DEFINITION | VerusConstants.MAPPING_ERC1155_NFT_DEFINITION) 
                    == VerusConstants.MAPPING_ETHEREUM_OWNED)
            {
                try callGetName(contracts[uint(VerusConstants.ContractType.TokenManager)]).getName(_tx[j].ERCContract) returns (string memory name) {
                    outputName = name;
                } catch {
                    // ... is illegal for a VerusID so we can use it to indicate that the name is not available
                    outputName = "...";
                }

                if (bytes(outputName).length == 0) {
                    continue;
                }
                outputName = string(abi.encodePacked("[", outputName, "] as "));
            }

            outputName = string(abi.encodePacked(outputName, _tx[j].name));

            if (_tx[j].parent != VERUS)
            {
                outputName = string(abi.encodePacked(outputName, ".", verusToERC20mapping[_tx[j].parent].name));
            }
            recordToken(_tx[j].iaddress, _tx[j].ERCContract, outputName, _tx[j].name, uint8(_tx[j].flags), _tx[j].tokenID);
        }
    }

    function recordToken(
        address _iaddress,
        address ethContractAddress,
        string memory name,
        string memory ticker,
        uint8 flags,
        uint256 tokenID
    ) public { 

        address ERCContract;

        if (flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) 
        {
            if (flags & VerusConstants.MAPPING_ERC20_DEFINITION == VerusConstants.MAPPING_ERC20_DEFINITION) 
            {
                Token t = new Token(name, ticker); 
                ERCContract = address(t); 
            }
            else if (flags & VerusConstants.MAPPING_ERC721_NFT_DEFINITION == VerusConstants.MAPPING_ERC721_NFT_DEFINITION)
            {
                ERCContract = verusToERC20mapping[tokenList[VerusConstants.NFT_POSITION]].erc20ContractAddress;
                tokenID = uint256(uint160(_iaddress)); //tokenID is the i address
            }
        }
        else 
        {
            ERCContract = ethContractAddress;
        }

        tokenList.push(_iaddress);
        // TokenIndex is not used so always set to 0, as this is the starting amount of currency the bridge owns for that currency.
        verusToERC20mapping[_iaddress] = VerusObjects.mappedToken(ERCContract, flags, 0, name, tokenID);
 
    }

    function processTransactions(bytes calldata serializedTransfers, uint8 numberOfTransfers) 
                external returns (bytes memory refundsData, uint64 fees)
    {

        VerusObjects.PackedSend[] memory transfers;
        VerusObjects.PackedCurrencyLaunch[] memory launchTxs;
        uint176[] memory refundAddresses;
        uint32 counter;
        (transfers, launchTxs, counter, refundAddresses) = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).deserializeTransfers(serializedTransfers, numberOfTransfers);
        
        // Only two currency launches are allowed per CCE, so use a third one to store fees, as function is to large.
        fees = uint64(launchTxs[2].tokenID);
        refundsData = importTransactions(transfers, refundAddresses);

        // 32bit counter is split into two 16bit values, the first 16bits is the number of transactions, the second 16bits is the number of currency launches
        if (uint8(counter >> 24) > 0) {
            launchToken(launchTxs);
        }

        //return and refund any failed transactions
        return (refundsData, fees);
    }

    function importTransactions(VerusObjects.PackedSend[] memory trans, uint176[] memory refundAddresses) private returns (bytes memory refundsData){
      

        for(uint256 i = 0; i < trans.length; i++)
        {
            uint64 sendAmount;
            address destinationAddress;
            address currencyiAddress;
            VerusObjects.mappedToken memory tempToken;
            uint8 result;

            sendAmount = uint64(trans[i].currencyAndAmount >> VerusConstants.UINT160_BITS_SIZE);
            destinationAddress  = address(uint160(trans[i].destinationAndFlags));
            tempToken = verusToERC20mapping[address(uint160(trans[i].currencyAndAmount))];
            currencyiAddress = address(uint160(trans[i].currencyAndAmount));
            
            if (currencyiAddress == VETH) 
            {
                result = uint8(SendTypes.ETH);            
            }   
            else if (tempToken.flags & VerusConstants.MAPPING_ERC20_DEFINITION == VerusConstants.MAPPING_ERC20_DEFINITION)
            {
                // if the ERC20 type is verus owned then mint the currency to the destination address, else transfer the currency to the destination address.
                result = uint8((tempToken.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED) 
                                                   ? SendTypes.ERC20MINT : SendTypes.ERC20);
            } 
            else if (tempToken.flags & VerusConstants.MAPPING_ETHEREUM_OWNED == VerusConstants.MAPPING_ETHEREUM_OWNED)
            {
                if (tempToken.flags & VerusConstants.MAPPING_ERC721_NFT_DEFINITION == VerusConstants.MAPPING_ERC721_NFT_DEFINITION) 
                {             
                    result = uint8(SendTypes.ERC721);

                } else if (tempToken.flags & VerusConstants.MAPPING_ERC1155_NFT_DEFINITION == VerusConstants.MAPPING_ERC1155_NFT_DEFINITION ||
                           tempToken.flags & VerusConstants.MAPPING_ERC1155_ERC_DEFINITION == VerusConstants.MAPPING_ERC1155_ERC_DEFINITION) 
                {
                    result = uint8(SendTypes.ERC1155);
                }
            }
            else if (tempToken.flags & VerusConstants.MAPPING_ERC721_NFT_DEFINITION == VerusConstants.MAPPING_ERC721_NFT_DEFINITION &&
                     tempToken.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED)
            {
                VerusNft t = VerusNft(tempToken.erc20ContractAddress);
                t.mint(currencyiAddress, tempToken.name, destinationAddress);
            }

            if(result > uint8(SendTypes.NULL)) {
                result = sendCurrencyToETHAddress(tempToken.erc20ContractAddress, destinationAddress, sendAmount, result, tempToken.tokenID); 
            }

            if (result == SEND_FAILED && sendAmount > 0) {
                refundsData = abi.encodePacked(refundsData, refundAddresses[i], sendAmount, currencyiAddress);
            } else if (result == SEND_SUCCESS) {
                verusToERC20mapping[currencyiAddress].tokenID -= sendAmount;
            } else if (result == SEND_SUCCESS_ERC1155) {
                // TokenIndex used for ERC1155 Acounting so decrement holdings if successful
                verusToERC20mapping[currencyiAddress].tokenIndex -= sendAmount;
            }

        } 
    }

    // Returns true if successful transfer
    function sendCurrencyToETHAddress(address tokenERCAddress, address destinationAddress, uint256 sendAmount, uint8 sendType, uint256 TokenId ) private returns (uint8){

            if(sendType == uint8(SendTypes.ETH)) {
                return payable(destinationAddress).send(sendAmount * VerusConstants.SATS_TO_WEI_STD) ? SEND_SUCCESS_ETH : SEND_FAILED;
            }
            Token token; 

            uint256 amount;
            if (sendType == uint8(SendTypes.ERC20) || sendType == uint8(SendTypes.ERC20MINT)) {
                token = Token(tokenERCAddress);  
                amount = convertFromVerusNumber(sendAmount, token.decimals());
            }

            if(sendType == uint8(SendTypes.ERC20)) {

                if (tokenERCAddress == DAIERC20ADDRESS)  {
                    address crossChainExportAddress = contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)];
                    (bool success,) = crossChainExportAddress.delegatecall(abi.encodeWithSelector(VerusCrossChainExport.exit.selector, destinationAddress, amount));
                    return success ? SEND_SUCCESS : SEND_FAILED;
                } else {
                    return token.transfer(destinationAddress, amount) ? SEND_SUCCESS : SEND_FAILED;
                }
            }
            else if(sendType == uint8(SendTypes.ERC20MINT)) {
                
                token.mint(destinationAddress, amount);
                return SEND_SUCCESS_ERC20_MINTED;
            }
            else if(sendType == uint8(SendTypes.ERC721)) {

                try IERC721(tokenERCAddress).transferFrom(address(this), destinationAddress, TokenId) {
                    return SEND_SUCCESS_ERC721; 
                } catch {
                    return SEND_FAILED; 
                }
            }
            else if(sendType == uint8(SendTypes.ERC1155)) {
                try IERC1155(tokenERCAddress).safeTransferFrom(address(this), destinationAddress, TokenId, sendAmount, "") {
                    return SEND_SUCCESS_ERC1155; 
                } catch {
                    return SEND_FAILED; 
                }

            } else {
                return SEND_FAILED;
            }
    }

    function convertFromVerusNumber(uint256 a, uint8 decimals) internal pure returns (uint256 c) {
            uint8 power = 10; //default value for 18

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