// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "../VerusBridge/VerusSerializer.sol";
import "../Storage/StorageMaster.sol";
import "./dsrinterface.sol";

contract VerusCrossChainExport is VerusStorage {
    
    VerusObjects.CCurrencyValueMap[] currencies;
    VerusObjects.CCurrencyValueMap[] fees;

    address immutable VETH;
    address immutable BRIDGE;
    address immutable VERUS;
    address immutable DAIERC20;

    address immutable pot;
    address immutable daiJoin;

    constructor(address vETH, address Bridge, address Verus, address daiERC20, address potAddress, address daiJoinAddress) {

        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
        DAIERC20 = daiERC20;
        pot = potAddress;
        daiJoin = daiJoinAddress;
    }

    function initialize() external {
        VatLike vat = VatLike(PotLike(pot).vat());
        vat.hope(daiJoin);
        vat.hope(pot);
        IERC20(DAIERC20).approve(daiJoin, uint256(int256(-1)));
    }

    uint256 constant RAY = 10 ** 27;
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = mul(x, y) / RAY;
    }
    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = mul(x, RAY) / y;
    }
    function rdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds up
        z = add(mul(x, RAY), sub(y, 1)) / y;
    }

    function quickSort(VerusObjects.CCurrencyValueMap[] storage currency, int left, int right) private {
        int i = left;
        int j = right;
        if (i == j) return;
        uint160 pivot = uint160(currency[uint256(left + (right - left) / 2)].currency);
        while (i <= j) {
            while (uint160(currency[uint256(i)].currency) < pivot) i++;
            while (pivot < uint160(currency[uint256(j)].currency)) j--;
            if (i <= j) {
                VerusObjects.CCurrencyValueMap memory temp = currency[uint256(i)];

                currency[uint256(i)] = currency[uint256(j)];
                currency[uint256(j)] = temp;
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(currency, left, j);
        if (i < right)
            quickSort(currency, i, right);
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

    function generateCCE(bytes memory bytesin) external returns(bytes memory){

        (VerusObjects.CReserveTransfer[] memory transfers, bool bridgeReady, uint64 startheight, uint64 endheight, address verusSerializer) = abi.decode(bytesin, (VerusObjects.CReserveTransfer[], bool, uint64, uint64, address));
        
        VerusObjects.CCrossChainExport memory workingCCE;
        //create a hash of the transfers and then 
        bytes memory serializedTransfers = VerusSerializer(verusSerializer).serializeCReserveTransfers(transfers, false);
        bytes32 hashedTransfers = keccak256(serializedTransfers);

        //create the Cross ChainExport to then serialize and hash
        
        workingCCE.version = 1;
        workingCCE.flags = 2;
        workingCCE.sourceheightstart = startheight;
        workingCCE.sourceheightend = endheight;
        workingCCE.sourcesystemid = VETH;
        workingCCE.hashtransfers = hashedTransfers;
        workingCCE.destinationsystemid = VERUS;

        if (bridgeReady) { 
            workingCCE.destinationcurrencyid = BRIDGE;  //NOTE:transfers are bundled by type
        } else {
            workingCCE.destinationcurrencyid = VERUS; 
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
                currencies[feeExistsInTotals - 1].amount += transfers[i].fees;
            } else {
                currencies.push(VerusObjects.CCurrencyValueMap(transfers[i].feecurrencyid, transfers[i].fees));
            }

            feeExists = inFees(transfers[i].feecurrencyid); 
            if(feeExists > 0){
                fees[feeExists - 1].amount += transfers[i].fees;
            } else {
                fees.push(VerusObjects.CCurrencyValueMap(transfers[i].feecurrencyid, transfers[i].fees));
            }
            
        }
        
        quickSort(currencies, int(0), int(currencies.length - 1));  //maps in the daemon are sorted, sort array.
        quickSort(fees, int(0), int(fees.length - 1));
               
        workingCCE.totalamounts = currencies;
        workingCCE.totalfees = fees; 

        VerusObjects.CCurrencyValueMap memory totalburnedCCVM = VerusObjects.CCurrencyValueMap(address(0), 0);

        workingCCE.totalburned = new VerusObjects.CCurrencyValueMap[](1);
        workingCCE.totalburned[0] = totalburnedCCVM;
        //workingCCE.rewardaddress is left empty as it is serialized to 0x0000

        workingCCE.firstinput = 1;

        // clear the arrays
        delete currencies;
        delete fees;

        return VerusSerializer(verusSerializer).serializeCCrossChainExport(workingCCE);

    }

    function daiBalance() external returns (uint256 wad) {
        uint256 chi = (block.timestamp > PotLike(pot).rho()) ? PotLike(pot).drip() : PotLike(pot).chi();
        wad = rmul(chi, claimableFees[VerusConstants.VDXFID_DAI_DSR_SUPPLY]);
    }

    // wad is denominated in dai
    function join(uint256 wad) external payable {
        uint256 chi = (block.timestamp > PotLike(pot).rho()) ? PotLike(pot).drip() : PotLike(pot).chi();
        uint256 pie = rdiv(wad, chi);
        claimableFees[VerusConstants.VDXFID_DAI_DSR_SUPPLY] = add(claimableFees[VerusConstants.VDXFID_DAI_DSR_SUPPLY], pie);
        claimableFees[VerusConstants.VDXF_SYSTEM_DAI_HOLDINGS] = add(claimableFees[VerusConstants.VDXF_SYSTEM_DAI_HOLDINGS], wad);
        JoinLike(daiJoin).join(address(this), wad);
        PotLike(pot).join(pie);
    }

    // wad is denominated in dai
    function exit(address dst, uint256 wad) external {
        uint256 chi = (block.timestamp > PotLike(pot).rho()) ? PotLike(pot).drip() : PotLike(pot).chi();
        uint256 pie = rdivup(wad, chi);

        claimableFees[VerusConstants.VDXFID_DAI_DSR_SUPPLY] = sub(claimableFees[VerusConstants.VDXFID_DAI_DSR_SUPPLY], pie);
        PotLike(pot).exit(pie);
        uint256 amt = rmul(chi, pie);
        claimableFees[VerusConstants.VDXF_SYSTEM_DAI_HOLDINGS] = sub(claimableFees[VerusConstants.VDXF_SYSTEM_DAI_HOLDINGS], amt) ;
        JoinLike(daiJoin).exit(dst, amt);
    }
}