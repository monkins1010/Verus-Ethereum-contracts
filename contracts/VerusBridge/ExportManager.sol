// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../Libraries/VerusConstants.sol";
import "../Storage/StorageMaster.sol";


contract ExportManager is VerusStorage  {

    uint8 constant FEE_OFFSET = 20 + 20 + 20 + 8; // 3 x 20bytes address + 64bit uint
    uint8 constant AUX_DEST_LENGTH = 24;

    function ERC20Registered(address _iaddress) private view returns (bool) {

        return verusToERC20mapping[_iaddress].flags > 0;
        
    }

    function checkExport(bytes calldata datain) external payable returns (uint256 fees){
       
        VerusObjects.CReserveTransfer memory transfer = abi.decode(datain, (VerusObjects.CReserveTransfer));

        require(ERC20Registered(transfer.currencyvalue.currency) && 
            ERC20Registered(transfer.feecurrencyid) &&
            ERC20Registered(transfer.destcurrencyid) &&
            (ERC20Registered(transfer.secondreserveid) || transfer.secondreserveid == address(0)) &&
            transfer.destsystemid == address(0), "currencycheckfailed");

        uint256 requiredFees = VerusConstants.transactionFee;  //0.003 eth in WEI (To vrsc)
        uint64 bounceBackFee;
        uint64 transferFee;
        bytes memory serializedDest;
        address gatewayID;
        address gatewayCode;
        address destAddressID;
        uint8 destinationType;

        require (checkTransferFlags(transfer), "Flag Check failed");                 
       
        // Check destination address is not zero
        serializedDest = transfer.destination.destinationaddress;  

        if (transfer.destination.destinationtype != VerusConstants.DEST_ETHNFT)
        {
            assembly 
            {
                destAddressID := mload(add(serializedDest, 20))
            }
        }
        else
        {
            // Custom destination for NFT  = 1byte desttype + 20bytes destinationaddres + 20bytes NFT address + 32bytes NFTTokenID
            require (transfer.destination.destinationaddress.length == VerusConstants.VERUS_NFT_DEST_LENGTH, "NFT destination address not 53 bytes");
            require (transfer.flags == VerusConstants.VALID, "Invalid flags for NFT transfer");
            require (transfer.currencyvalue.amount == 1, "Currency value must be 1 Satoshi");
            assembly 
            {
                destinationType := mload(add(serializedDest, 1))
                destAddressID := mload(add(serializedDest, 21))
            }
            require (destinationType == VerusConstants.DEST_PKH ||
                   destinationType == VerusConstants.DEST_ID  ||
                   destinationType == VerusConstants.DEST_SH, "NFT destination not valid");

        }
        require (destAddressID != address(0), "Destination Address null");// Destination can be currency definition
        // Check fees are correct, if pool unavailble vrsctest only fees, TODO:if pool availble vETH fees only for now

        if (!poolAvailable) {

            require (transfer.feecurrencyid == VerusConstants.VerusCurrencyId, "feecurrencyid != vrsc");
            
            //VRSC pool as WEI
            if (!(transfer.destination.destinationtype == VerusConstants.DEST_PKH ||
                   transfer.destination.destinationtype == VerusConstants.DEST_ID  ||
                   transfer.destination.destinationtype == VerusConstants.DEST_SH))
                    return 0;

            if (!(transfer.secondreserveid == address(0) && transfer.destcurrencyid == VerusConstants.VerusCurrencyId
                    && transfer.flags == VerusConstants.VALID))
                return 0;

            require (transfer.destination.destinationaddress.length == 20, "destination address not 20 bytes");

        } else {
            
            transferFee = uint64(transfer.fees);

            require(transfer.feecurrencyid == VerusConstants.VEth, "Fee Currency not vETH"); //TODO:Accept more fee currencies

            if (transfer.flags == VerusConstants.VALID)
            {
                require(transfer.destcurrencyid == VerusConstants.VerusBridgeAddress, "flagsnotvalid");
            }

            if ((transfer.destination.destinationtype & ~VerusConstants.FLAG_DEST_AUX) == (VerusConstants.FLAG_DEST_GATEWAY + VerusConstants.DEST_ETH)) {

                //destination is concatenated with the gateway back address (bridge.veth) + (gatewayCode) + 0.003 ETH in fees uint64LE
                
                require (transfer.destination.destinationaddress.length == (FEE_OFFSET + AUX_DEST_LENGTH) ||
                        transfer.destination.destinationaddress.length == (FEE_OFFSET), "destination address not 68 or (+ 24 bytes)");
                require (transfer.currencyvalue.currency != transfer.secondreserveid, "Bounce back type not allowed");
                assembly 
                {
                    gatewayID := mload(add(serializedDest, 40)) // second 20bytes in bytes array
                    gatewayCode := mload(add(serializedDest, 60)) // third 20bytes in bytes array
                    bounceBackFee := mload(add(serializedDest, FEE_OFFSET))
                }

                require (gatewayID == VerusConstants.VEth, "GatewayID not VETH");
                require (gatewayCode == address(0), "GatewayCODE must be empty");

                bounceBackFee = reverse(bounceBackFee);
                require (bounceBackFee >= VerusConstants.verusvETHReturnFee, "Return fee not >= 0.01ETH");

                transferFee += bounceBackFee;
                requiredFees += convertFromVerusNumber(uint256(bounceBackFee),18);  //bounceback fees required as well as send fees

            } else if (!(transfer.destination.destinationtype == VerusConstants.DEST_PKH || transfer.destination.destinationtype == VerusConstants.DEST_ID 
                        || transfer.destination.destinationtype == VerusConstants.DEST_SH || transfer.destination.destinationtype == VerusConstants.DEST_ETHNFT)) {

                return 0;  

            } 

        }

        // Check fees are included in the ETH value if sending ETH, or are equal to the fee value for tokens.
        uint amount;
        amount = transfer.currencyvalue.amount;

        if (poolAvailable)
        { 
            if (convertFromVerusNumber(transferFee, 18) < requiredFees)
            {
                revert ("ETH Fees to Low");
            }            
            else if (transfer.currencyvalue.currency == VerusConstants.VEth && 
                msg.value < convertFromVerusNumber(uint256(amount + transferFee), 18))
            {
                revert ("ETH sent < (amount + fees)");
            } 
            else if (transfer.currencyvalue.currency != VerusConstants.VEth &&
                    msg.value < convertFromVerusNumber(transferFee, 18))
            {
                revert ("ETH fee sent < fees for token");
            } 

            return transferFee;
        }
        else 
        {
            if (transfer.fees != VerusConstants.verusTransactionFee)
            {
                revert ("Invalid VRSC fee");
            }
            else if (transfer.currencyvalue.currency == VerusConstants.VEth &&
                     (convertFromVerusNumber(amount, 18) + requiredFees) != msg.value)
            {
                revert ("ETH Fee to low");
            }
            else if(transfer.currencyvalue.currency != VerusConstants.VEth && requiredFees != msg.value)
            {
                revert ("ETH Fee to low (token)");
            }
        } 
        return requiredFees;
    }

    function checkTransferFlags(VerusObjects.CReserveTransfer memory transfer) public view returns(bool) {

        if (transfer.version != VerusConstants.CURRENT_VERSION || (transfer.flags & (VerusConstants.INVALID_FLAGS | VerusConstants.VALID) ) != VerusConstants.VALID)
            return false;

        uint8 transferType = transfer.destination.destinationtype & ~VerusConstants.FLAG_DEST_GATEWAY;
        
        VerusObjects.mappedToken memory sendingCurrency = verusToERC20mapping[transfer.currencyvalue.currency];
        VerusObjects.mappedToken memory destinationCurrency = verusToERC20mapping[transfer.destcurrencyid];

        if (transfer.destination.destinationtype == (VerusConstants.DEST_ETH + VerusConstants.FLAG_DEST_GATEWAY)
                && (transfer.flags & VerusConstants.CURRENCY_EXPORT  != VerusConstants.CURRENCY_EXPORT))
        {
            if (transfer.flags == (VerusConstants.VALID + VerusConstants.CONVERT + VerusConstants.RESERVE_TO_RESERVE))
            {
                require(sendingCurrency.flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH &&
                        destinationCurrency.flags & VerusConstants.MAPPING_ISBRIDGE_CURRENCY == VerusConstants.MAPPING_ISBRIDGE_CURRENCY &&
                        verusToERC20mapping[transfer.secondreserveid].flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH,
                         "Cannot convert non bridge reserves");
            }
            else if (transfer.flags == (VerusConstants.VALID + VerusConstants.CONVERT + VerusConstants.IMPORT_TO_SOURCE))
            {
                require(sendingCurrency.flags & VerusConstants.MAPPING_ISBRIDGE_CURRENCY == VerusConstants.MAPPING_ISBRIDGE_CURRENCY  &&
                        destinationCurrency.flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH,
                         "Cannot import non reserve to source");
            }
            else if (transfer.flags == (VerusConstants.VALID + VerusConstants.CONVERT))
            {
                require(sendingCurrency.flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH  &&
                        destinationCurrency.flags & VerusConstants.MAPPING_ISBRIDGE_CURRENCY == VerusConstants.MAPPING_ISBRIDGE_CURRENCY,
                         "Cannot convert non reserve");
            }
            else 
            {
                return false;
            }

            return true;
        }
        else if (transfer.flags == (VerusConstants.CURRENCY_EXPORT + VerusConstants.VALID) && transferType == VerusConstants.DEST_REGISTERCURRENCY)
        {
            // TODO: upgrade contract to handle ERC721's registered by the contract (currently only from mapped currencies from the daemon)
            // NFT currency export definition.  Contains ERC721 contract address and token ID. 
            // NOTE: Check when importing a currency check the fees and gateway
            // can be sent to DEST_ID / DEST_PKH / DEST_SH
            return false; /* NFTS NOT CURRENCTLY ACTIVATED */
        }
        else if (transferType != VerusConstants.DEST_ID && 
                 transferType != VerusConstants.DEST_PKH && 
                 transferType != VerusConstants.DEST_SH &&
                 transferType != VerusConstants.DEST_ETHNFT)
        {
            return false;
        }
        else
        {
            if (transfer.flags == VerusConstants.VALID)
            {
                return true;
            }
            else if (transfer.flags == (VerusConstants.VALID + VerusConstants.CONVERT + VerusConstants.RESERVE_TO_RESERVE))
            {
                require(sendingCurrency.flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH &&
                        destinationCurrency.flags & VerusConstants.MAPPING_ISBRIDGE_CURRENCY == VerusConstants.MAPPING_ISBRIDGE_CURRENCY &&
                        verusToERC20mapping[transfer.secondreserveid].flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH,
                         "Cannot convert non bridge reserves");
            }
            else if (transfer.flags ==  (VerusConstants.VALID + VerusConstants.CONVERT + VerusConstants.IMPORT_TO_SOURCE))
            {
                require(sendingCurrency.flags & VerusConstants.MAPPING_ISBRIDGE_CURRENCY == VerusConstants.MAPPING_ISBRIDGE_CURRENCY  &&
                        destinationCurrency.flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH,
                         "Cannot import non reserve to source");
            }
            else if (transfer.flags ==  (VerusConstants.VALID + VerusConstants.CONVERT))
            {
                require(sendingCurrency.flags & VerusConstants.MAPPING_PARTOF_BRIDGEVETH == VerusConstants.MAPPING_PARTOF_BRIDGEVETH &&
                        destinationCurrency.flags & VerusConstants.MAPPING_ISBRIDGE_CURRENCY == VerusConstants.MAPPING_ISBRIDGE_CURRENCY,
                         "Cannot convert to source");
            }
            else
            {
                return false;
            }
            return true;
        }  
    }

    function reverse(uint64 input) public pure returns (uint64 v) 
    {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = (v >> 32) | (v << 32);
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