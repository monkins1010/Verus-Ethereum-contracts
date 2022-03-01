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


    function checkExport(VerusObjects.CReserveTransfer memory transfer, uint256 ETHSent) public view returns (uint256 fees){

       // function returns 0 for low level errors, however uses requires for higher level errors.

       require(tokenManager.ERC20Registered(transfer.currencyvalue.currency) && 
                tokenManager.ERC20Registered(transfer.feecurrencyid) &&
                tokenManager.ERC20Registered(transfer.destcurrencyid) &&
                (tokenManager.ERC20Registered(transfer.secondreserveid) || 
                transfer.secondreserveid == address(0)) &&
                transfer.destsystemid == address(0),
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

        require (ETHSent >= requiredFees, "ETH msg fees to low"); //TODO:ETH fees always required for now

        if (transfer.feecurrencyid == VerusConstants.VEth) {

            require (convertFromVerusNumber(transfer.fees,18) >= requiredFees, "Fee value in transfer too low");

        }

        if (verusBridge.isPoolUnavailable(transfer.fees, transfer.feecurrencyid)) {

            if (!(transfer.destination.destinationtype == VerusConstants.DEST_PKH ||
                   transfer.destination.destinationtype == VerusConstants.DEST_ID))
                    return 0;

            if (!(transfer.secondreserveid == address(0) && transfer.destcurrencyid == VerusConstants.VEth))
                return 0;

            if (transfer.feecurrencyid == VerusConstants.VerusCurrencyId) {

                require (convertFromVerusNumber(transfer.fees,18) == verusFees, "VRSC fees not 0.02");
                require (transfer.destination.destinationaddress.length == 20, "destination address not 20 bytes");

            } else {

                require (false,"Fees must be in VRSC before pool is launched");

            }

        } else {

            require(transfer.destsystemid == VerusConstants.VEth, "Fee Currency not vETH"); //TODO:Accept more fee currencies

            if (transfer.destination.destinationtype & VerusConstants.FLAG_DEST_GATEWAY == VerusConstants.FLAG_DEST_GATEWAY) {

                if (!(transfer.destination.destinationtype == (VerusConstants.FLAG_DEST_GATEWAY & VerusConstants.DEST_PKH )  ||
                   transfer.destination.destinationtype == (VerusConstants.FLAG_DEST_GATEWAY & VerusConstants.DEST_ID )     ||
                   transfer.destination.destinationtype == (VerusConstants.FLAG_DEST_GATEWAY & VerusConstants.DEST_ETH )))
                    return 0;

                require (transfer.destination.destinationaddress.length == (20 + 20 + 8), "destination address not 48 bytes");

                serializedDest = transfer.destination.destinationaddress;   
                assembly {
                    gatewayID := mload(add(serializedDest, 40))
                    bounceBackFee := mload(add(serializedDest, FEE_OFFSET))
                }

                assert (gatewayID == VerusConstants.VEth);
                require (convertFromVerusNumber(bounceBackFee, 18) >= requiredFees, "Return fee not large enough");

                requiredFees += requiredFees;  //TODO: bounceback fees required as well as send fees

                 require (ETHSent >= requiredFees, "ETH fees to low"); //TODO:ETH fees always required for now

            } else if (!(transfer.destination.destinationtype == VerusConstants.DEST_PKH || transfer.destination.destinationtype == VerusConstants.DEST_ID 
                        || transfer.destination.destinationtype == VerusConstants.DEST_ETH )) {

                return 0;

            } 

        }

        // Check fees are included in the ETH value if sending ETH, or are equal to the fee value for tokens.
       
        if (transfer.currencyvalue.currency == VerusConstants.VEth) {

            require (ETHSent == (requiredFees + convertFromVerusNumber(transfer.currencyvalue.amount,18)), "ETH sent != (amount + fees)");
      
        } else {

            require (ETHSent == requiredFees, "ETH fee sent != (amount + fees)");
        }

        return requiredFees;
    }

    function checkReadyExports() public view returns(address) {

           
        (uint created , bool readyBlock) = verusBridge.readyExportsByBlock(block.number);

        if (readyBlock) {
    
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

        if (transfer.version != 1 || (transfer.flags & (VerusConstants.INVALID_FLAGS | VerusConstants.VALID) ) > 1)
            return false;

        if (transfer.destination.destinationtype == (VerusConstants.DEST_ETH & VerusConstants.FLAG_DEST_GATEWAY))
        {
            // ensure that this is prepared properly for valid bounce back

            if (transfer.destcurrencyid == VerusConstants.VerusBridgeAddress) {

                if (!(transfer.flags == (VerusConstants.VALID & VerusConstants.CONVERT & VerusConstants.RESERVE_TO_RESERVE) &&
                    ( transfer.secondreserveid == VerusConstants.VEth || 
                      transfer.secondreserveid == VerusConstants.VerusSystemId || 
                      transfer.secondreserveid == VerusConstants.VerusUSDCId
                    ))) {
                        return false;

                } else if (transfer.flags == (VerusConstants.VALID & VerusConstants.CONVERT ) &&
                        transfer.secondreserveid != address(0)
                    ) { 
                        return false;               
                }

            } else if (!(transfer.flags == (VerusConstants.VALID & VerusConstants.CONVERT & VerusConstants.IMPORT_TO_SOURCE) &&
                        (transfer.destcurrencyid == VerusConstants.VEth || 
                         transfer.destcurrencyid == VerusConstants.VerusSystemId || 
                         transfer.destcurrencyid == VerusConstants.VerusUSDCId 
                  ))) {
                        return false;
            } else {

                return false;
            }

        }
        else if (transfer.destination.destinationtype != VerusConstants.DEST_ID && 
                 transfer.destination.destinationtype != VerusConstants.DEST_PKH && 
                 transfer.destination.destinationtype != VerusConstants.DEST_SH)
        {
            return false;
        }
        else
        {
             // ensure that all other values are valid as send to Verus without bounce back
        
            if (transfer.flags == VerusConstants.VALID &&
                transfer.destcurrencyid != VerusConstants.VerusSystemId) {
                    return false;
            } 
            else if (transfer.flags == (VerusConstants.VALID & VerusConstants.CONVERT) &&
                transfer.destcurrencyid != VerusConstants.VerusBridgeAddress) {
                    return false;
            } 
            else if (!(transfer.flags == (VerusConstants.VALID & VerusConstants.CONVERT & VerusConstants.IMPORT_TO_SOURCE) &&
                      (transfer.secondreserveid == VerusConstants.VEth || 
                      transfer.secondreserveid == VerusConstants.VerusSystemId || 
                      transfer.secondreserveid == VerusConstants.VerusUSDCId))) {
                    return false;
            } 
            else if (!(transfer.flags == (VerusConstants.VALID & VerusConstants.CONVERT & VerusConstants.RESERVE_TO_RESERVE) &&
                      transfer.destcurrencyid == VerusConstants.VerusBridgeAddress &&
                      (transfer.secondreserveid == VerusConstants.VEth || 
                      transfer.secondreserveid == VerusConstants.VerusSystemId ||
                      transfer.secondreserveid == VerusConstants.VerusUSDCId))) {
                    return false;
            } else {

                return false;
            }
        
        }
   
        return true;
    }

}