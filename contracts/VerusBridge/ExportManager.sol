// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../Libraries/VerusConstants.sol";
import "./TokenManager.sol";
import "../VerusBridge/VerusBridgeStorage.sol";

contract ExportManager {

    TokenManager tokenManager;
    VerusBridgeStorage verusBridgeStorage;
    address verusUpgradeContract;

    constructor(address verusBridgeStorageAddress, address tokenManagerAddress, address verusUpgradeAddress)
    {
        verusBridgeStorage = VerusBridgeStorage(verusBridgeStorageAddress); 
        tokenManager = TokenManager(tokenManagerAddress);
        verusUpgradeContract = verusUpgradeAddress;
    }

    function setContract(address _contract) public {

        assert(msg.sender == verusUpgradeContract);
        
        if(_contract != address(tokenManager)) 
        {
            tokenManager = TokenManager(_contract);
        }

    }

    function checkExport(VerusObjects.CReserveTransfer memory transfer, uint256 ETHSent, bool poolAvailable) public view  returns (uint256 fees){

        verusBridgeStorage.checkiaddresses(transfer);

        uint256 requiredFees =  VerusConstants.transactionFee;  //0.003 eth in WEI
        uint256 verusFees = VerusConstants.verusTransactionFee; //0.02 verus in SATS
        uint64 bounceBackFee;
        uint8  FEE_OFFSET = 20 + 20 + 20 + 8; // 3 x 20bytes address + 64bit uint
        bytes memory serializedDest;
        address gatewayID;
        address destAddressID;
        
        require (checkTransferFlags(transfer), "Flag Check failed");         
                                  
        //TODO: We cant mix different transfer destinations together in the CCE assert on non same fields.
        address destCurrencyexportID = verusBridgeStorage.getCreatedExport(block.number);

        require (destCurrencyexportID == address(0) || destCurrencyexportID == transfer.destcurrencyid, "checkReadyExports cannot mix types ");
        
        // Check destination address is not zero
        serializedDest = transfer.destination.destinationaddress;  

        assembly {
                    destAddressID := mload(add(serializedDest, 20))
                 }

        require (destAddressID != address(0), "Destination Address null");// Destination can be currency definition

        // Check fees are correct, if pool unavailble vrsctest only fees, TODO:if pool availble vETH fees only for now

        require (ETHSent >= requiredFees, "ETH msg fees to low"); //TODO:ETH fees always required for now

        if (transfer.feecurrencyid == VerusConstants.VEth) {

            require (tokenManager.convertFromVerusNumber(transfer.fees,18) >= requiredFees, "Fee value in transfer too low");

        }


        if (!poolAvailable) {

            require (transfer.feecurrencyid == VerusConstants.VerusCurrencyId, "feecurrencyid != vrsc");
            
            //VRSC pool as WEI
            if (!(transfer.destination.destinationtype == VerusConstants.DEST_PKH ||
                   transfer.destination.destinationtype == VerusConstants.DEST_ID  ||
                   transfer.destination.destinationtype == VerusConstants.DEST_SH))
                    return 0;

            if (!(transfer.secondreserveid == address(0) && transfer.destcurrencyid == VerusConstants.VerusCurrencyId))
                return 0;

            require (transfer.fees == verusFees, "VRSC fees not 0.02");
            require (transfer.destination.destinationaddress.length == 20, "destination address not 20 bytes");


        } else {

            require(transfer.feecurrencyid == VerusConstants.VEth, "Fee Currency not vETH"); //TODO:Accept more fee currencies

            if (transfer.destination.destinationtype == (VerusConstants.FLAG_DEST_GATEWAY | VerusConstants.DEST_ETH )) {

                require (transfer.destination.destinationaddress.length == (20 + 20 + 20 + 8), "destination address not 68 bytes");

                assembly {
                    gatewayID := mload(add(serializedDest, 40)) // second 20bytes in bytes array
                    bounceBackFee := mload(add(serializedDest, FEE_OFFSET))
                }

                require (gatewayID == VerusConstants.VEth, "GateswayID not VETH");
                require (tokenManager.convertFromVerusNumber(bounceBackFee, 18) >= requiredFees, "Return fee not >0.003ETH");

                requiredFees += requiredFees;  //TODO: bounceback fees required as well as send fees

                 require (ETHSent >= requiredFees, "ETH fees to low"); //TODO:ETH fees always required for now

            } else if (!(transfer.destination.destinationtype == VerusConstants.DEST_PKH || transfer.destination.destinationtype == VerusConstants.DEST_ID 
                        || transfer.destination.destinationtype == VerusConstants.DEST_SH )) {

                return 0;  

            } 

        }

        // Check fees are included in the ETH value if sending ETH, or are equal to the fee value for tokens.
       
        if (transfer.currencyvalue.currency == VerusConstants.VEth) {

            require (ETHSent >= (requiredFees + tokenManager.convertFromVerusNumber(transfer.currencyvalue.amount,18)), "ETH sent < (amount + fees)");
      
        } else {

            require (ETHSent >= requiredFees, "ETH fee sent < (amount + fees)");
        }

        return requiredFees;
    }

    function checkTransferFlags(VerusObjects.CReserveTransfer memory transfer) public pure returns(bool) {

        if (transfer.version != VerusConstants.CURRENT_VERSION || (transfer.flags & (VerusConstants.INVALID_FLAGS | VerusConstants.VALID) ) != VerusConstants.VALID)
            return false;

        uint8 transferType = transfer.destination.destinationtype & ~VerusConstants.FLAG_DEST_GATEWAY;
        //TODO: Hardening CertainCReserveTransfer flag combinations are still invalid. 
        if (transfer.destination.destinationtype == (VerusConstants.DEST_ETH + VerusConstants.FLAG_DEST_GATEWAY)
                && (transfer.flags & VerusConstants.CURRENCY_EXPORT  != VerusConstants.CURRENCY_EXPORT))
        {
            return true;
        }
        else if (transfer.flags == VerusConstants.CURRENCY_EXPORT && transferType == VerusConstants.DEST_REGISTERCURRENCY)
        {
            return true;
        }
        else if ((transferType != VerusConstants.DEST_ID && 
                transferType != VerusConstants.DEST_PKH && 
                transferType != VerusConstants.DEST_SH) )
        {
            return false;
        }
        else
        {
            return true;
        }
   
        
    }

}