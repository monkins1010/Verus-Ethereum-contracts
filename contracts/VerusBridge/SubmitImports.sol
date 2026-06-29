// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "./Token.sol";
import "../Storage/StorageMaster.sol";
import "./CreateExports.sol";
import "./TokenManager.sol";

interface IVerusToken {
    function supply() external view returns (uint256);
}


contract SubmitImports is VerusStorage {

    address immutable VETH;
    address immutable BRIDGE;
    address immutable VERUS;
    address immutable DAI;
    address immutable MKR;
    address immutable PROTOCOL_FEE_RECIPIENT;
    uint256 immutable DEPLOYED_AT;
    uint256 constant THREE_YEARS = 3 * 365 days;

    constructor(address vETH, address Bridge, address Verus, address Dai, address Mkr, address protocolFeeRecipient){

        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
        DAI = Dai;
        MKR = Mkr;
        PROTOCOL_FEE_RECIPIENT = protocolFeeRecipient;
        DEPLOYED_AT = block.timestamp;
    }

    uint32 constant ELVCHOBJ_TXID_OFFSET = 32;
    uint32 constant ELVCHOBJ_NVINS_OFFSET = 45;
    // Minimum byte length of a valid CTransactionHeader elVchObj:
    // 32 (txHash) + 1 (struct ver) + 4 (nVersion) + 4 (nVersionGroupId) + 4*4 (counts) = 57
    uint32 constant ELVCHOBJ_MIN_LENGTH = 57;
    // CTransactionHeader struct version — only version 1 is supported; other values mean
    // the field layout is unknown and the offsets below would be wrong.
    uint8 constant HEADER_STRUCT_VERSION = 1;
    // Offset used to read the struct-version byte: mload(elVchObj+33) puts data[32] in the
    // rightmost (uint8) position of the 32-byte word.
    uint32 constant ELVCHOBJ_STRUCT_VERSION_OFFSET = 33;
    uint32 constant ELVCHOBJ_NVOUTS_OFFSET = 49;
    uint32 constant ELVCHOBJ_NSHIELDEDSPENDS_OFFSET = 53;
    uint32 constant ELVCHOBJ_NSHIELDEDOUTPUTS_OFFSET = 57;
    uint32 constant FORKS_NOTARY_PROPOSER_POSITION = 96;
    uint32 constant TYPE_REFUND = 1;
    uint constant TYPE_BYTE_LOCATION_IN_UINT176 = 168;
    uint8 constant TYPE_REFUND_BYTES32_LOCATION = 244;
    bytes32 constant SUBMIT_IMPORTS_REENTRANCY_GUARD = "submitimports.reentrancy.lock";
    enum Currency {VETH, DAI, VERUS, MKR}

    // Parsed fields from the CTransactionHeader serialized in components[0].elVchObj.
    // nLockTime, nExpiryHeight and nValueBalance are not needed and are excluded.
    struct TxHeaderData {
        bytes32 txHash;
        uint32 nVins;
        uint32 nVouts;
        uint32 nShieldedSpends;
        uint32 nShieldedOutputs;
    }

    function initialize() external {
        
    }

    // Parse the CTransactionHeader from components[0].elVchObj.
    // Layout (all counts are LE uint32):
    //   bytes  0-31 : txHash
    //   byte   32   : CTransactionHeader struct version
    //   bytes 33-36 : tx nVersion
    //   bytes 37-40 : nVersionGroupId
    //   bytes 41-44 : nVins
    //   bytes 45-48 : nVouts
    //   bytes 49-52 : nShieldedSpends
    //   bytes 53-56 : nShieldedOutputs
    function _parseTxHeader(bytes memory elVchObj) private pure returns (TxHeaderData memory hdr) {
        // Reject anything too short to contain all required fields; reading beyond the
        // allocated bytes would silently return zeroes and produce a wrong elHashSize.
        require(elVchObj.length >= ELVCHOBJ_MIN_LENGTH);

        // Validate the CTransactionHeader struct version (byte at data[32]).  Only version 1
        // is defined; any other value means the field offsets below are invalid.
        uint8 hdrStructVer;
        assembly { hdrStructVer := mload(add(elVchObj, ELVCHOBJ_STRUCT_VERSION_OFFSET)) }
        require(hdrStructVer >= HEADER_STRUCT_VERSION);

        uint32 v;
        bytes32 txHash;
        assembly { txHash := mload(add(elVchObj, ELVCHOBJ_TXID_OFFSET)) }
        hdr.txHash = txHash;

        assembly { v := mload(add(elVchObj, ELVCHOBJ_NVINS_OFFSET)) }
        v = ((v & 0xFF00FF00) >> 8) | ((v & 0x00FF00FF) << 8);
        hdr.nVins = (v >> 16) | (v << 16);

        assembly { v := mload(add(elVchObj, ELVCHOBJ_NVOUTS_OFFSET)) }
        v = ((v & 0xFF00FF00) >> 8) | ((v & 0x00FF00FF) << 8);
        hdr.nVouts = (v >> 16) | (v << 16);

        assembly { v := mload(add(elVchObj, ELVCHOBJ_NSHIELDEDSPENDS_OFFSET)) }
        v = ((v & 0xFF00FF00) >> 8) | ((v & 0x00FF00FF) << 8);
        hdr.nShieldedSpends = (v >> 16) | (v << 16);

        assembly { v := mload(add(elVchObj, ELVCHOBJ_NSHIELDEDOUTPUTS_OFFSET)) }
        v = ((v & 0xFF00FF00) >> 8) | ((v & 0x00FF00FF) << 8);
        hdr.nShieldedOutputs = (v >> 16) | (v << 16);
    }

    function buildReserveTransfer (uint64 value, uint176 sendTo, address sendingCurrency, uint64 fees, address feecurrencyid) private view returns (VerusObjects.CReserveTransfer memory) {
        
        VerusObjects.CReserveTransfer memory LPtransfer;
      
        LPtransfer.version = 1;
        LPtransfer.destination.destinationtype = uint8(sendTo >> TYPE_BYTE_LOCATION_IN_UINT176);
        LPtransfer.destcurrencyid = BRIDGE;
        LPtransfer.destsystemid = address(0);
        LPtransfer.secondreserveid = address(0);
        LPtransfer.flags = VerusConstants.VALID;
        LPtransfer.destination.destinationaddress = abi.encodePacked(uint160(sendTo));
        LPtransfer.currencyvalue.currency = sendingCurrency;
        LPtransfer.feecurrencyid = feecurrencyid;
        LPtransfer.fees = fees;
        LPtransfer.currencyvalue.amount = value;          
        
        return LPtransfer;
    }

    function sendBurnBackToVerus (uint64 sendAmount, address currency, uint64 fees) external view returns (VerusObjects.CReserveTransfer memory) {
        
        VerusObjects.CReserveTransfer memory LPtransfer;

        if (currency == VERUS) {
            LPtransfer =  buildReserveTransfer(uint64(remainingLaunchFeeReserves - VerusConstants.verusTransactionFee),
                                               uint176(VerusConstants.VDXFID_VETH_BURN_ADDRESS),
                                               VERUS,
                                               VerusConstants.verusTransactionFee,
                                               VERUS );
        } else if (currency == DAI) {
            LPtransfer =  buildReserveTransfer(sendAmount,
                                               uint176(VerusConstants.VDXFID_VETH_BURN_ADDRESS),
                                               DAI,
                                               fees,
                                               DAI );
        } 

        LPtransfer.flags += VerusConstants.BURN_CHANGE_PRICE ;

        return LPtransfer;
    }

    function getImportFeeForReserveTransfer(address currency) public view returns (uint64) {
        
        uint64 feeShare;
        uint feeCalculation;
        uint reserves = claimableFees[bytes32(uint256(uint160(VerusConstants.VDXF_ETH_DAI_VRSC_LAST_RESERVES)))];

        // Get the uint64 location in the uint256 word to calculate fees
        if (currency == DAI){
            feeCalculation = uint(Currency.DAI) << 6;
        } else if (currency == MKR){
            feeCalculation = uint(Currency.MKR) << 6;
        } else if (currency == VETH) {
            feeCalculation = uint(Currency.VETH) << 6;
        } else if (currency == VERUS) {
            return uint64(VerusConstants.VERUS_IMPORT_FEE);
        } else {
            // NOTE: Bridge.vETH currency is not supported.
            revert();
        }      
            
        feeCalculation = VerusConstants.VERUS_IMPORT_FEE_X2 * uint64(reserves >> feeCalculation);
        feeShare = uint64(feeCalculation / uint(uint64(reserves >> (uint(Currency.VERUS) << 6))));

        return feeShare;
    }

    function _createImports(bytes calldata data) external returns(uint64, uint176) {

        require(storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD].length == 0, "Reentrancy guard");
        storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD] = abi.encodePacked(uint8(1));

        if (claimableFees[VerusConstants.VDXF_DISABLE_CONTRACT_KEY] & VerusConstants.HALT_SUBMIT_IMPORTS != 0) revert();

        uint256 gasleftStart = gasleft();
        VerusObjects.CReserveTransferImport memory _import = abi.decode(data, (VerusObjects.CReserveTransferImport));

        // Parse CTransactionHeader from component 0 and validate the txid is not a replay.
        TxHeaderData memory hdr = _parseTxHeader(_import.partialtransactionproof.components[0].elVchObj);

        if (processedTxids[hdr.txHash]) 
        {
            revert();
        } 

        bool success;
        bytes memory returnBytes;
        bytes32 hashOfTransfers = keccak256(_import.serializedTransfers);
        uint128 CCEHeightsAndnIndex;
        // exporters[0]=main dest, exporters[1]=first aux, exporters[2]=second aux
        uint176[3] memory exporters;

        // Scope A: build txCounts and delegatecall proveImports (txCounts released after block)
        {
            uint128 txCounts = uint128(1 + 2 * hdr.nVins + hdr.nVouts + hdr.nShieldedSpends + hdr.nShieldedOutputs)
                | (uint128(hdr.nVins) << 32)
                | (uint128(hdr.nVouts) << 64)
                | (uint128(hdr.nShieldedSpends) << 96);
            (success, returnBytes) = contracts[uint(VerusConstants.ContractType.VerusProof)].delegatecall(
                abi.encodeWithSignature("proveImports(bytes)", abi.encode(_import, hashOfTransfers, txCounts))
            );
            require(success);
        }

        // Scope B: decode 3 exporters into array (temps e0/e1/e2 released after block)
        {
            uint176 e0; uint176 e1; uint176 e2;
            (CCEHeightsAndnIndex, e0, e1, e2) = abi.decode(returnBytes, (uint128, uint176, uint176, uint176));
            uint176 flagMask = 0x0fffffffffffffffffffffffffffffffffffffffffff;
            exporters[0] = e0 & flagMask;
            exporters[1] = e1 & flagMask;
            exporters[2] = e2 & flagMask;
        }

        isLastCCEInOrder(uint32(CCEHeightsAndnIndex));
   
        // clear 4 bytes above first 64 bits, i.e. clear the nIndex 32 bit number, then convert to correct nIndex
        // Using the index for the proof (ouput of an export) - (header ( 2 * nvin )) == export output
        // NOTE: This depends on the serialization of the CTransaction header and the location of the vins being 45 bytes in.
        // NOTE: Also depends on it being a partial transaction proof, header = 1

        CCEHeightsAndnIndex  = (CCEHeightsAndnIndex & 0xffffffff00000000ffffffffffffffff) | (uint128(uint32(uint32(CCEHeightsAndnIndex >> 64) - (1 + (2 * hdr.nVins)))) << 64);  
        setLastImport(hdr.txHash, hashOfTransfers, CCEHeightsAndnIndex);
        
        // get the gasleft before calling the tokenmanager

        //returns success, refund addresses bytes & refund address array which is abi.encoded-ed, these are any refunds that didnt pay out.
        (success, returnBytes) = contracts[uint(VerusConstants.ContractType.TokenManager)].delegatecall(abi.encodeWithSelector(TokenManager.processTransactions.selector, _import.serializedTransfers, uint256(uint32(CCEHeightsAndnIndex >> 96))));
        require(success);

        uint176[] memory refundAddresses;
        uint64 fees;

        // returns refundaddresses bytes, fees and refundaddresses
        (returnBytes, fees, refundAddresses) = abi.decode(returnBytes, (bytes, uint64, uint176[]));

        // get the cceblockwidth of the cce from endheight - startheight and copy back into CCEHeightsAndnIndex
        CCEHeightsAndnIndex = (uint32(CCEHeightsAndnIndex >> 32) - uint32(CCEHeightsAndnIndex));

        // calculate the fee to pay any refunds, and then pay to the refund addresses.
        calulateGasFees(gasleftStart, fees, refundAddresses, CCEHeightsAndnIndex, exporters);

        if (returnBytes.length > 0) {
            refund(returnBytes);
        }

        delete storageGlobal[SUBMIT_IMPORTS_REENTRANCY_GUARD];

        return (0,0);
    }

    function calulateGasFees(uint256 gasStart, uint64 fees, uint176[] memory refundAddresses, uint256 blockWidth, uint176[3] memory exporters) private {

        uint256 priceOfImports; // ETH price of the imports calculated from gas used.
        uint64 notaryFees;   // fees to pay to notaries
        uint64 blockDivisor; // ratio adjustment when traffic is high
        uint64 minTxesForRefund; // minimum number of transactions for a refund
        uint64 feeRefunds;
        uint64 processorsFees; // fees shared out between notaries / exporters / proposers.

        // Using the gas used gives us an indication of how much the transaction will cost.
        // i.e. the gas used to do 2 * notaryimports + fixedcost for submitimport + (gas to process the tx payements)
        uint256 reimbursablePrice = block.basefee + VerusConstants.MAX_TIP;
        priceOfImports = uint256((gasStart - gasleft()) + VerusConstants.GAS_BASE_COST_FOR_NOTARYS + 
            (refundAddresses.length * VerusConstants.GAS_BASE_COST_FOR_REFUND_PAYOUTS)) 
            * reimbursablePrice;

        // Use a Buffer of 40% for notary fees. (In Verus sats)
        notaryFees = uint64(((priceOfImports * 14) / 10) / VerusConstants.SATS_TO_WEI_STD); 

        if (fees > (notaryFees + (notaryFees >> 4))){

            blockDivisor = 20;
            minTxesForRefund = VerusConstants.MINIMUM_TRANSACTIONS_FOR_REFUNDS;

            if (blockWidth > 1)
            {
                blockDivisor = 10;
                minTxesForRefund = VerusConstants.MINIMUM_TRANSACTIONS_FOR_REFUNDS_HALF;
            }

            if (refundAddresses.length > minTxesForRefund)
            {
                processorsFees = fees - notaryFees;
                fees = notaryFees;

                feeRefunds = uint64((processorsFees / refundAddresses.length) * (refundAddresses.length - minTxesForRefund));
                feeRefunds = feeRefunds - (feeRefunds / blockDivisor);
                processorsFees = processorsFees - feeRefunds;

                // Divide by number of transactions to get refund share per number of transfers.
                feeRefunds = feeRefunds / uint64(refundAddresses.length);

                for(uint i = 0; i < refundAddresses.length; i++) {
                    bytes32 feeRefundAddress;
                    feeRefundAddress = bytes32(uint256(refundAddresses[i]));

                    if (feeRefundAddress != bytes32(0)) {
                        feeRefundAddress |= bytes32(uint256(TYPE_REFUND) << TYPE_REFUND_BYTES32_LOCATION);
                        refunds[feeRefundAddress][VETH] += feeRefunds;
                    } else {
                        processorsFees += feeRefunds;                    
                    }
                }
            } else {
                processorsFees = fees - notaryFees;
                fees = notaryFees;
            }
        } 

        setClaimableFees(fees, exporters, processorsFees);
    }
  
    function refund(bytes memory refundAmount) private  {

        if (refundAmount.length < 50) return; //early return if no refunds.

        // Note each refund is 50 bytes = 22bytes(uint176) + uint64 + uint160 (currency)
        for(uint i = 0; i < refundAmount.length; i = i + 50) {

            uint176 verusAddress;
            uint64 amount;
            address currency;
            assembly 
            {
                verusAddress := mload(add(add(refundAmount, 22), i))
                amount := mload(add(add(refundAmount, 30), i))
                currency := mload(add(add(refundAmount, 50), i))
            }

            bytes32 refundAddress;

            // The leftmost byte is the TYPE_REFUND;
            refundAddress = bytes32(uint256(verusAddress) | uint256(TYPE_REFUND) << TYPE_REFUND_BYTES32_LOCATION);

            refunds[refundAddress][currency] += amount;

        }
     }

    function setLastImport(bytes32 processedTXID, bytes32 hashofTXs, uint128 CCEheightsandTXNum ) private {

        processedTxids[processedTXID] = true;
       // lastTxIdImport = processedTXID;
        lastImportInfo[VerusConstants.SUBMIT_IMPORTS_LAST_TXID] = VerusObjects.lastImportInfo(hashofTXs, processedTXID, uint32(CCEheightsandTXNum >> 64), uint32(CCEheightsandTXNum >> 32));
    } 

    function isLastCCEInOrder(uint32 height) private view {
      
        if ((lastImportInfo[VerusConstants.SUBMIT_IMPORTS_LAST_TXID].height + 1) == height)
        {
            return;
        } 
        else if (lastImportInfo[VerusConstants.SUBMIT_IMPORTS_LAST_TXID].hashOfTransfers == bytes32(0))
        {
            return;
        } 
        else{
            revert();
        }
    }
    
    function getReadyExportsByRange(uint _startBlock,uint _endBlock) external view returns(VerusObjects.CReserveTransferSetCalled[] memory returnedExports){
    
        uint outputSize;
        uint heights = _startBlock;
        bool loop = cceLastEndHeight > 0;

        if(!loop) return returnedExports;

        while(loop){

            heights = _readyExports[heights].endHeight + 1;
            if (heights > _endBlock || heights == 1) {
                break;
            }
            outputSize++;
        }

        returnedExports = new VerusObjects.CReserveTransferSetCalled[](outputSize);
        VerusObjects.CReserveTransferSet memory tempSet;
        heights = _startBlock;

        for (uint i = 0; i < outputSize; i++)
        {
            tempSet = _readyExports[heights];
            returnedExports[i] = VerusObjects.CReserveTransferSetCalled(tempSet.exportHash, tempSet.prevExportHash, uint64(heights), tempSet.endHeight, tempSet.transfers);
            heights = tempSet.endHeight + 1;
        }
        return returnedExports;      
    }

    function setClaimableFees(uint64 notaryFees, uint176[3] memory exporters, uint64 processorsFees) private 
    {
        uint64 feeShare;
        feeShare = processorsFees / 3;
        bytes32 notaryPoolKey = VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL;

        claimableFees[notaryPoolKey] += (notaryFees + feeShare);
           
        if (processorsFees > 0) {

            bytes memory proposerBytes = bestForks[0];
            uint176 proposer;
            require(proposerBytes.length >= FORKS_NOTARY_PROPOSER_POSITION + 22);
            assembly {
                    proposer := mload(add(proposerBytes, FORKS_NOTARY_PROPOSER_POSITION))
            }

            // Keep processorsFees fully conserved:
            // notary pool gets feeShare, proposer gets feeShare, exporter/protocol get the remainder.
            uint64 exporterTotal = processorsFees - (feeShare << 1);
            uint64 exporterHalf  = exporterTotal / 2;
            uint64 protocolShare = exporterTotal - exporterHalf;

            setClaimedFees(bytes32(uint256(proposer)), feeShare); // 1/3 to proposer
            setClaimedFees(bytes32(uint256(exporters[1])), exporterHalf); // half of exporter share to exporter[1]

            bool redirectProtocolShare = false;
            if (block.timestamp >= DEPLOYED_AT + THREE_YEARS) {
                (bool ok, bytes memory ret) = PROTOCOL_FEE_RECIPIENT.staticcall(abi.encodeWithSelector(IVerusToken.supply.selector));
                if (ok && ret.length >= 32) {
                    uint256 verusTokenSupply = abi.decode(ret, (uint256));
                    redirectProtocolShare = PROTOCOL_FEE_RECIPIENT.balance >= verusTokenSupply;
                }
            }

            if (redirectProtocolShare) {
                setClaimedFees(bytes32(uint256(exporters[0])), protocolShare);
            } else {
                (bool success, ) = payable(PROTOCOL_FEE_RECIPIENT).call{value: protocolShare * VerusConstants.SATS_TO_WEI_STD }("");
                require(success);

            }
        }
    }

    function setClaimedFees(bytes32 _address, uint256 fees) private  {

        claimableFees[_address] += fees;
    }

    function claimfees() external {

        uint256 claimAmount;

        if ((claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL] * VerusConstants.SATS_TO_WEI_STD) > VerusConstants.CLAIM_NOTARY_FEE_THRESHOLD)
        {
            uint256 txReimburse;

            // truncate reimburse amount
            uint256 reimbursablePrice = block.basefee + VerusConstants.MAX_TIP;
            txReimburse = ((reimbursablePrice * VerusConstants.NOTARY_CLAIM_TX_GAS_COST) / VerusConstants.SATS_TO_WEI_STD) * VerusConstants.SATS_TO_WEI_STD;

            if (claimableFees[bytes32(0)] > 0) {
                // When there is no proposer fees are sent to bytes(0)
                claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL] += claimableFees[bytes32(0)];
                claimableFees[bytes32(0)] = 0;
            }

            claimAmount = claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL] - (txReimburse / VerusConstants.SATS_TO_WEI_STD);

            claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL] = 0;

            uint256 claimShare;
            
            claimShare = claimAmount / notaries.length;
            bool success;
            for (uint i = 0; i < notaries.length; i++)
            {
                if (notaryAddressMapping[notaries[i]].state == VerusConstants.NOTARY_VALID)
                {
                    claimAmount -= claimShare;
                    (success, ) = payable(notaryAddressMapping[notaries[i]].main).call{value: claimShare * VerusConstants.SATS_TO_WEI_STD}("");
                    require(success);
                }
            }
            claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL] = claimAmount;
            (success, ) = payable(msg.sender).call{value: txReimburse}("");
            require(success);
        }
    }

    function claimRefund(uint176 verusAddress, address currency) external payable returns (uint)
    {
        uint256 refundAmount;
        bytes32 refundAddressFormatted;
        VerusObjects.CReserveTransfer memory LPtransfer;
        bool success;
        refundAddressFormatted = bytes32(uint256(verusAddress) | uint256(TYPE_REFUND) << TYPE_REFUND_BYTES32_LOCATION);

        refundAmount = refunds[refundAddressFormatted][currency];
        require (bridgeConverterActive && refundAmount > 0 && verusAddress != uint176(0));
        
        delete refunds[refundAddressFormatted][currency];
        uint64 fees;
        address feeCurrency;

        if (currency != VETH && currency != DAI && currency != VERUS && currency != MKR) {
            fees = getImportFeeForReserveTransfer(VETH);
            if (msg.value < (fees * VerusConstants.SATS_TO_WEI_STD)) {
                revert();
            }
            //The user may have put too much in, so update fees for correct accounting.
            fees = uint64(msg.value / VerusConstants.SATS_TO_WEI_STD);
            feeCurrency = VETH;
        } else {
            fees = getImportFeeForReserveTransfer(currency);
            require (refundAmount > fees);
            feeCurrency = currency;
        }

        LPtransfer = buildReserveTransfer(uint64(refundAmount), verusAddress, currency, fees, feeCurrency);

        (success, ) = contracts[uint(VerusConstants.ContractType.CreateExport)]
                            .delegatecall(abi.encodeWithSelector(CreateExports.externalCreateExportCallPayable.selector, abi.encode(LPtransfer, false)));
        require(success);

        return 0;
  
    }

    // Caclulates the amount of DAI, MKR or VERUS to reimburse the user for the transaction fee.
    function getTxFeeReimbursement (address currency) private view returns (uint64) {

        uint256 txReimburse;
        // keep the Reimburse value in wei until end for accuracy
        uint256 reimbursablePrice = block.basefee + VerusConstants.MAX_TIP;
        txReimburse = (reimbursablePrice * VerusConstants.REFUND_FEE_REIMBURSE_GAS_AMOUNT);

        uint reserves = claimableFees[bytes32(uint256(uint160(VerusConstants.VDXF_ETH_DAI_VRSC_LAST_RESERVES)))];
        uint feeCalculation;
        // multiply the ETH amount by the reserve of ETH
        // Get the uint64 location in the uin256 word to calculate fees
        if (currency == DAI){
            feeCalculation = uint(Currency.DAI) << 6;
        } else if (currency == MKR){
            feeCalculation = uint(Currency.MKR) << 6;
        } else if (currency == VERUS) {
            feeCalculation = uint(Currency.VERUS) << 6;
        } else {
            // NOTE: Bridge.vETH currency is not supported.
            revert();
        }      

        // multiply the ETH amount by the reserves of the chosen currency
        txReimburse = txReimburse * uint64(reserves >> feeCalculation);
        txReimburse = (txReimburse / uint(uint64(reserves >> (uint(Currency.VETH) << 6)))) / VerusConstants.SATS_TO_WEI_STD;

        return uint64(txReimburse);

    }

    function sendfees(bytes32 publicKeyX, bytes32 publicKeyY) external 
    {
        require(bridgeConverterActive);
        uint8 leadingByte;
        uint256 claimant; 
        uint64 feeShare;

        leadingByte = (uint256(publicKeyY) & 1) == 1 ? 0x03 : 0x02;
        claimant = uint160(ripemd160(abi.encodePacked(sha256(abi.encodePacked(leadingByte, publicKeyX)))));
        claimant |= (uint256(0x0214) << VerusConstants.UINT160_BITS_SIZE);  // is Claimient type R address and 20 bytes.

        if ((claimableFees[bytes32(claimant)] > VerusConstants.verusvETHTransactionFee) 
                && msg.sender == address(uint160(uint256(keccak256(abi.encodePacked(publicKeyX, publicKeyY))))))
        {
            feeShare = uint64(claimableFees[bytes32(claimant)]);
            claimableFees[bytes32(claimant)] = 0;
            (bool success, ) = payable(msg.sender).call{value: feeShare * VerusConstants.SATS_TO_WEI_STD }("");
            require(success);
            return;
        }

        if ((claimableFees[publicKeyX] > (VerusConstants.verusvETHTransactionFee << 1))) {
            require(publicKeyX[10]  == 0x04);
            require(claimableFees[publicKeyX] > VerusConstants.verusvETHTransactionFee);
            feeShare = uint64(claimableFees[publicKeyX]) - VerusConstants.verusvETHTransactionFee;
            claimableFees[publicKeyX] = 0;
            VerusObjects.CReserveTransfer memory LPtransfer;
            LPtransfer = buildReserveTransfer(feeShare, uint176(uint256(publicKeyX)), VETH, VerusConstants.verusvETHTransactionFee, VETH);
            (bool success, ) = contracts[uint(VerusConstants.ContractType.CreateExport)]
                                .delegatecall(abi.encodeWithSelector(CreateExports.externalCreateExportCallPayable.selector, abi.encode(LPtransfer, false)));
            require(success);
        }
    
    }
}