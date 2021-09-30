// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../VerusBridge/VerusSerializer.sol";

contract VerusCrossChainExport{

    VerusObjects.CCurrencyValueMap[] currencies;
    VerusObjects.CCurrencyValueMap[] fees;
    VerusSerializer verusSerializer;
 //   event test1(VerusObjects.CCrossChainExport ted);

    function quickSort(VerusObjects.CCurrencyValueMap[] storage currencey, int left, int right) private {
        int i = left;
        int j = right;
        if (i == j) return;
        uint160 pivot = uint160(currencey[uint160(left + (right - left) / 2)].currency);
        while (i <= j) {
            while (uint160(currencey[uint160(i)].currency) < pivot) i++;
            while (pivot < uint160(currencey[uint160(j)].currency)) j--;
            if (i <= j) {
                VerusObjects.CCurrencyValueMap memory temp = currencey[uint160(i)];

                currencey[uint160(i)] = currencey[uint160(j)];
                currencey[uint160(j)] = temp;
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(currencey, left, j);
        if (i < right)
            quickSort(currencey, i, right);
    }

    constructor(address _verusSerializerAddress) {
        verusSerializer = VerusSerializer(_verusSerializerAddress);
    }

    function inCurrencies(address checkCurrency) private view returns(int64){
        for(uint i = 0; i < uint64(currencies.length); i++){
            if(currencies[i].currency == checkCurrency) return int64(i);
        }
        return -1;
    }

    function inFees(address checkFeesCurrency) private view returns(int64){
        for(uint i = 0; i < uint64(fees.length); i++){
            if(fees[i].currency == checkFeesCurrency) return int64(i);
        }
        return -1;
    }

    function generateCCE(VerusObjects.CReserveTransfer[] memory transfers) public returns(VerusObjects.CCrossChainExport memory){

        VerusObjects.CCrossChainExport memory workingCCE;
        //create a hash of the transfers and then 
        bytes memory serializedTransfers = verusSerializer.serializeCReserveTransfers(transfers,false);
        bytes32 hashedTransfers = keccak256(serializedTransfers);

        //create the Cross ChainExport to then serialize and hash
        
        workingCCE.version = 1;
        workingCCE.flags = 2;
        //workingCCE.flags = 1;
        //need to pick up the 
        workingCCE.sourceheightstart = uint32(block.number);
        workingCCE.sourceheightend = uint32(block.number);
        workingCCE.sourcesystemid = VerusConstants.VEth;
        workingCCE.destinationsystemid = VerusConstants.VerusSystemId;
        workingCCE.destinationcurrencyid = transfers[0].destcurrencyid;
        workingCCE.numinputs = uint32(transfers.length);
        //loop through the array and create totals of the amounts and fees
        
        int64 currencyExists;
        int64 feeExistsInTotals;
        int64 feeExists;

        for(uint i = 0; i < transfers.length; i++){
            currencyExists = inCurrencies(transfers[i].currencyvalue.currency);
            if(currencyExists >= 0){
                currencies[uint256(currencyExists)].amount += transfers[i].currencyvalue.amount;
            } else {
                currencies.push(VerusObjects.CCurrencyValueMap(transfers[i].currencyvalue.currency,transfers[i].currencyvalue.amount));
            }
            
            //add the fees into the totalamounts too 
            feeExistsInTotals = inCurrencies(transfers[i].feecurrencyid); 
            if(feeExistsInTotals >= 0){
                currencies[uint256(feeExistsInTotals)].amount += uint64(transfers[i].fees);
            } else {
                currencies.push(VerusObjects.CCurrencyValueMap(transfers[i].feecurrencyid,uint64(transfers[i].fees)));
            }

            feeExists = inFees(transfers[i].feecurrencyid); 
            if(feeExists >= 0){
                fees[uint256(feeExists)].amount += uint64(transfers[i].fees);
            } else {
                fees.push(VerusObjects.CCurrencyValueMap(transfers[i].feecurrencyid,uint64(transfers[i].fees)));
            }
            
        }
        
        quickSort(currencies, int(0), int(currencies.length - 1));
        quickSort(fees, int(0), int(fees.length - 1));
               
        workingCCE.totalamounts = currencies;
        workingCCE.totalfees = fees;

        workingCCE.hashtransfers = hashedTransfers;
        VerusObjects.CCurrencyValueMap memory totalburnedCCVM = VerusObjects.CCurrencyValueMap(0x0000000000000000000000000000000000000000,0);
        
        workingCCE.totalburned = new VerusObjects.CCurrencyValueMap[](1);
        workingCCE.totalburned[0] = totalburnedCCVM;
        workingCCE.rewardaddress = VerusObjectsCommon.CTransferDestination(VerusConstants.RewardAddressType,address(VerusConstants.RewardAddress));
        workingCCE.firstinput = 1;

        //clear the arrays
        delete currencies;
        delete fees;
      //  emit test1(workingCCE);
        return workingCCE;

    }
    


}