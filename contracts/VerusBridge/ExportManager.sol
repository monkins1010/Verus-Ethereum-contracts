// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../Libraries/VerusConstants.sol";
import "./TokenManager.sol";
import "../VerusBridge/VerusBridge.sol";

contract ExportManager {

    TokenManager tokenManager;
    VerusBridge verusBridge;

    constructor(
        address tokenManagerAddress,
        address verusBridgeAddress) public {
        tokenManager = TokenManager(tokenManagerAddress);
        verusBridge = VerusBridge(verusBridgeAddress);
    }

    uint32 constant  VALID = 1;
    uint32 constant  CONVERT = 2;
    uint32 constant  CROSS_SYSTEM = 0x40;               
    uint32 constant  IMPORT_TO_SOURCE = 0x200;          
    uint32 constant  RESERVE_TO_RESERVE = 0x400; 

    uint32 constant INVALID_FLAGS = 0xffffffff - (VALID + CONVERT + CROSS_SYSTEM + RESERVE_TO_RESERVE + IMPORT_TO_SOURCE);

    uint8 constant DEST_PKH = 2;
    uint8 constant DEST_ID = 4;
    uint8 constant DEST_ETH = 9;
    uint8 constant FLAG_DEST_GATEWAY = 128;

    function checkExport(VerusObjects.CReserveTransfer memory transfer, uint256 ETHSent) public view returns (uint256 fees){

       // function returns 0 for low level errors, however uses requires for higher level errors.

       require(tokenManager.ERC20Registered(transfer.currencyvalue.currency) && 
                tokenManager.ERC20Registered(transfer.feecurrencyid) &&
                tokenManager.ERC20Registered(transfer.destcurrencyid) &&
                (tokenManager.ERC20Registered(transfer.secondreserveid) || 
                transfer.secondreserveid == address(0)) ,
                "One or more currencies has not been registered");

        uint256 requiredFees =  VerusConstants.transactionFee;  //0.003 eth in WEI
        uint256 verusFees = VerusConstants.verusTransactionFee; //0.02 verus in SATS
        uint64 bounceBackFee;
        uint8  FEE_OFFSET = 20 + 20 + 8;
        bytes memory serializedDest = new bytes(20 + 20 + 8);
        address gatewayID;
        address destAddressID;

        
        if (!checkTransferFlags(transfer))
            return 0;
                                  
        require(transfer.destsystemid == VerusConstants.VerusCurrencyId, "Destination system not VRSC"); //Always VRSCTEST

        //TODO: We cant mix different transfer destinations together in the CCE assert on non same fields.
        address exportID = checkReadyExports();
        
        if (exportID != address(0))
        {
               assert (exportID != transfer.destcurrencyid);

        }

        // Check destination address is not zero
        serializedDest = transfer.destination.destinationaddress;  

            assembly {
                destAddressID := mload(add(serializedDest, 20))
            }

        if (destAddressID == address(0))
            return 0;

        // Check fees are correct, if pool unavailble vrsctest only fees, TODO:if pool availble vETH fees only for now

        require(ETHSent >= requiredFees, "ETH msg fees to low"); //TODO:ETH fees always required for now

        if(transfer.feecurrencyid == VerusConstants.VEth) {

            require(convertFromVerusNumber(transfer.fees,18) >= requiredFees, "Fee value in transfer too low");

        }

        if (verusBridge.isPoolUnavailable(transfer.fees, transfer.feecurrencyid)) {

            if(!(transfer.destination.destinationtype == DEST_PKH ||
                   transfer.destination.destinationtype == DEST_ID))
                    return 0;

            if(!(transfer.secondreserveid == address(0) && transfer.destcurrencyid == VerusConstants.VEth))
                return 0;

            if(transfer.feecurrencyid == VerusConstants.VerusCurrencyId) {

                require(convertFromVerusNumber(transfer.fees,18) == verusFees, "VRSC fees not 0.02");
                require(transfer.destination.destinationaddress.length == 20, "destination address not 20 bytes");

            } else {

                require(false,"Fees must be in VRSC before pool is launched");

            }

        } else {

            require(transfer.destsystemid == VerusConstants.VEth, "Fee Currency not vETH"); //TODO:Accept more fee currencies

            if(transfer.destination.destinationtype & FLAG_DEST_GATEWAY == FLAG_DEST_GATEWAY) {

                if(!(transfer.destination.destinationtype == (FLAG_DEST_GATEWAY & DEST_PKH )  ||
                   transfer.destination.destinationtype == (FLAG_DEST_GATEWAY & DEST_ID )     ||
                   transfer.destination.destinationtype == (FLAG_DEST_GATEWAY & DEST_ETH )))
                    return 0;

                require(transfer.destination.destinationaddress.length == (20 + 20 + 8), "destination address not 48 bytes");

                serializedDest = transfer.destination.destinationaddress;   
                assembly {
                    gatewayID := mload(add(serializedDest, 40))
                    bounceBackFee := mload(add(serializedDest, FEE_OFFSET))
                }

                assert(gatewayID == VerusConstants.VEth);
                require(convertFromVerusNumber(bounceBackFee, 18) >= requiredFees, "Return fee not large enough");

                requiredFees += requiredFees;  //TODO: bounceback fees required as well as send fees

                 require(ETHSent >= requiredFees, "ETH fees to low"); //TODO:ETH fees always required for now

            } else if (!(transfer.destination.destinationtype == DEST_PKH || transfer.destination.destinationtype == DEST_ID 
                        || transfer.destination.destinationtype == DEST_ETH )) {

                return 0;

            } 

        }

        // Check fees are included in the ETH value if sending ETH, or are equal to the fee value for tokens.
       
        if(transfer.currencyvalue.currency == VerusConstants.VEth) {

            require(ETHSent == (requiredFees + convertFromVerusNumber(transfer.currencyvalue.amount,18)), "ETH sent != (amount + fees)");
      
        } else {

            require(ETHSent == requiredFees, "ETH fee sent != (amount + fees)");
        }

        return requiredFees;
    }

    function checkReadyExports() public view returns(address) {

           
        (uint created , bool readyBlock) = verusBridge.readyExportsByBlock(block.number);

        if(readyBlock) {
    
            return verusBridge.getCreatedExport(created);

        } else {

            return address(0);
        }

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

    function checkTransferFlags(VerusObjects.CReserveTransfer memory transfer) public view returns(bool) {

        if (transfer.version != 1 || (transfer.flags & INVALID_FLAGS) > 0)
            return false;

        if(!(transfer.flags & VALID == VALID))
            return false;

       
        if(transfer.destination.destinationtype == DEST_ID || transfer.destination.destinationtype == DEST_PKH ) {

            if(transfer.destcurrencyid == VerusConstants.VEth)
                return false;

        } else if (transfer.destination.destinationtype & DEST_ETH == DEST_ETH &&
                   transfer.destination.destinationtype & FLAG_DEST_GATEWAY == FLAG_DEST_GATEWAY ) {

            if(transfer.currencyvalue.currency == VerusConstants.VerusBridgeAddress) {

                if(transfer.destcurrencyid == VerusConstants.VerusBridgeAddress)
                    return false;

            } else {

                if(transfer.destcurrencyid != VerusConstants.VerusBridgeAddress)
                    return false;

            }

        } else {

            return false;

        }

        if(!(transfer.flags & IMPORT_TO_SOURCE == IMPORT_TO_SOURCE ||
           transfer.flags & RESERVE_TO_RESERVE == RESERVE_TO_RESERVE)) {

               if(transfer.flags & CONVERT != CONVERT) {
                   if(transfer.destcurrencyid != VerusConstants.VerusBridgeAddress ||
                       transfer.destcurrencyid != VerusConstants.VerusCurrencyId )
                       return false;

               } else {

                    if(transfer.destcurrencyid != VerusConstants.VerusBridgeAddress)
                       return false;

               }
        }

        if(transfer.flags & IMPORT_TO_SOURCE == IMPORT_TO_SOURCE) {

            if(transfer.destcurrencyid == VerusConstants.VerusBridgeAddress ||
                transfer.flags & RESERVE_TO_RESERVE == RESERVE_TO_RESERVE ||
                 transfer.flags & CONVERT != CONVERT )
                return false;

        }

        if(transfer.flags & RESERVE_TO_RESERVE == RESERVE_TO_RESERVE) {

            if(transfer.destcurrencyid == VerusConstants.VerusBridgeAddress ||
                transfer.flags & IMPORT_TO_SOURCE == IMPORT_TO_SOURCE ||
                 transfer.flags & CONVERT != CONVERT )
                return false;

            if(transfer.destination.destinationtype & FLAG_DEST_GATEWAY == FLAG_DEST_GATEWAY) { 

                if(transfer.secondreserveid == VerusConstants.VerusBridgeAddress )
                    return false;

            } else {

                if(transfer.destcurrencyid != VerusConstants.VerusBridgeAddress )
                    return false;

            }

        }
   
        return true;
    }

}