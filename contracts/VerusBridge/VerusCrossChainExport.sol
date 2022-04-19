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

    address upgradeContract;

    constructor(address verusSerializerAddress, address upgradeAddress) {
        verusSerializer = VerusSerializer(verusSerializerAddress);
        upgradeContract = upgradeAddress;
    }

    function setContract(address contractAddress) public {

        require(msg.sender == upgradeContract);

        verusSerializer = VerusSerializer(contractAddress);

    }

    function quickSort(VerusObjects.CCurrencyValueMap[] storage currencey, int left, int right) private {
        int i = left;
        int j = right;
        if (i == j) return;
        uint160 pivot = uint160(currencey[uint256(left + (right - left) / 2)].currency);
        while (i <= j) {
            while (uint160(currencey[uint256(i)].currency) < pivot) i++;
            while (pivot < uint160(currencey[uint256(j)].currency)) j--;
            if (i <= j) {
                VerusObjects.CCurrencyValueMap memory temp = currencey[uint256(i)];

                currencey[uint256(i)] = currencey[uint256(j)];
                currencey[uint256(j)] = temp;
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(currencey, left, j);
        if (i < right)
            quickSort(currencey, i, right);
    }

    function inCurrencies(address checkCurrency) private view returns(uint256){
        for(uint256 i = 0; i < currencies.length; i++){
            if(currencies[i].currency == checkCurrency) return i + 1;
        }
        return 0;
    }

    function inFees(address checkFeesCurrency) private view returns(uint256){
        for(uint256 i = 0; i < fees.length; i++){
            if(fees[i].currency == checkFeesCurrency) return i + 1;
        }
        return 0;
    }

    function generateCCE(VerusObjects.CReserveTransfer[] memory transfers, bool bridgeReady) public returns(VerusObjects.CCrossChainExport memory){

        VerusObjects.CCrossChainExport memory workingCCE;
        //create a hash of the transfers and then 
        bytes memory serializedTransfers = verusSerializer.serializeCReserveTransfers(transfers, false);
        bytes32 hashedTransfers = keccak256(serializedTransfers);

        //create the Cross ChainExport to then serialize and hash
        
        workingCCE.version = 1;
        workingCCE.flags = 2;
        workingCCE.sourceheightstart = uint32(block.number);
        workingCCE.sourceheightend = uint32(block.number);
        workingCCE.sourcesystemid = VerusConstants.VEth;
        workingCCE.hashtransfers = hashedTransfers;
        workingCCE.destinationsystemid = VerusConstants.VerusSystemId;

        if (bridgeReady) { // RESERVETORESERVE FLAG
            workingCCE.destinationcurrencyid = VerusConstants.VerusBridgeAddress;  //TODO:transfers are bundled by type
        } else {
            workingCCE.destinationcurrencyid = VerusConstants.VerusCurrencyId; //TODO:transfers are bundled by type
        }

        workingCCE.numinputs = uint32(transfers.length);
        //loop through the array and create totals of the amounts and fees
        
        uint256 currencyExists;
        uint256 feeExistsInTotals;
        uint256 feeExists;

        for(uint i = 0; i < transfers.length; i++){
            currencyExists = inCurrencies(transfers[i].currencyvalue.currency);
            if(currencyExists > 0){
                currencies[currencyExists - 1].amount += transfers[i].currencyvalue.amount;
            } else {
                currencies.push(VerusObjects.CCurrencyValueMap(transfers[i].currencyvalue.currency,transfers[i].currencyvalue.amount));
            }
            
            //add the fees into the totalamounts too 
            feeExistsInTotals = inCurrencies(transfers[i].feecurrencyid); 
            if(feeExistsInTotals > 0){
                currencies[feeExistsInTotals - 1].amount += uint64(transfers[i].fees);
            } else {
                currencies.push(VerusObjects.CCurrencyValueMap(transfers[i].feecurrencyid,uint64(transfers[i].fees)));
            }

            feeExists = inFees(transfers[i].feecurrencyid); 
            if(feeExists > 0){
                fees[feeExists - 1].amount += uint64(transfers[i].fees);
            } else {
                fees.push(VerusObjects.CCurrencyValueMap(transfers[i].feecurrencyid,uint64(transfers[i].fees)));
            }
            
        }
        
        quickSort(currencies, int(0), int(currencies.length - 1));
        quickSort(fees, int(0), int(fees.length - 1));
               
        workingCCE.totalamounts = currencies;
        workingCCE.totalfees = fees; 

        VerusObjects.CCurrencyValueMap memory totalburnedCCVM = VerusObjects.CCurrencyValueMap(0x0000000000000000000000000000000000000000,0);

        workingCCE.totalburned = new VerusObjects.CCurrencyValueMap[](1);
        workingCCE.totalburned[0] = totalburnedCCVM;
        workingCCE.rewardaddress = VerusObjectsCommon.CTransferDestination(VerusConstants.RewardAddressType, abi.encodePacked(VerusConstants.RewardAddress));
        workingCCE.firstinput = 1;

        // clear the arrays
        delete currencies;
        delete fees;

        // emit test1(workingCCE);
        return workingCCE;

    }
    
}