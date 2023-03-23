// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "./Token.sol";
import "../Storage/StorageMaster.sol";

contract CreateExport is VerusStorage {

    function subtractPoolSize(uint64 _amount) private returns (bool) {

        if(_amount > poolSize) return false;
        poolSize -= _amount;
        return true;
    }
 
    function export(bytes calldata data) payable external {

        uint256 fees;

        VerusObjects.CReserveTransfer memory transfer = abi.decode(data, (VerusObjects.CReserveTransfer));

        address verusExportManagerAddress = mapper.getLogicContract(uint(VerusConstants.ContractType.ExportManager));

        (bool success, bytes memory feeBytes) = verusExportManagerAddress.call(abi.encodeWithSignature("checkExport(bytes,uint256,bool)", data, msg.value, poolAvailable));
        require(success);

        fees = abi.decode(feeBytes, (uint256)); //fees = exportManager.checkExport(transfer, paidValue, poolAvailable);

        require(fees != 0, "CheckExport Failed Checks"); 

        if(!poolAvailable)
        {
            require (subtractPoolSize(uint64(transfer.fees)));
        }

        if (transfer.currencyvalue.currency != VerusConstants.VEth && transfer.destination.destinationtype != VerusConstants.DEST_ETHNFT) {

            VerusObjects.mappedToken memory mappedContract = verusToERC20mapping[transfer.currencyvalue.currency];
            Token token = Token(mappedContract.erc20ContractAddress); 
            //Check user has allowed the verusBridgeStorage contract to spend on their behalf
            uint256 allowedTokens = token.allowance(msg.sender, address(this));
            uint256 tokenAmount = convertFromVerusNumber(transfer.currencyvalue.amount, token.decimals()); //convert to wei from verus satoshis
            require( allowedTokens >= tokenAmount);
            //transfer the tokens to the verusbridgemaster contract
            //total amount kept as wei until export to verus
            exportERC20Tokens(tokenAmount, token, mappedContract.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED, msg.sender );
            
        } else if (transfer.destination.destinationtype == VerusConstants.DEST_ETHNFT){
            //handle a NFT Import
                
            address destinationAddress;
            uint8 desttype;
            address nftContract;
            uint256 tokenId;
            bytes memory serializedDest;
            serializedDest = transfer.destination.destinationaddress;  
            // 1byte desttype + 20bytes destinationaddres + 20bytes NFT address + 32bytes NFTTokenI
            assembly
            {
                desttype := mload(add(serializedDest, 1))
                destinationAddress := mload(add(serializedDest, 21))
                tokenId := mload(add(serializedDest, 53))  // cant have constant in assebmly == VerusConstants.VERUS_NFT_DEST_LENGTH
            }

            VerusObjects.mappedToken memory mappedContract = verusToERC20mapping[transfer.currencyvalue.currency];
            nftContract = mappedContract.erc20ContractAddress;
            require (serializedDest.length == VerusConstants.VERUS_NFT_DEST_LENGTH && (desttype == VerusConstants.DEST_PKH || desttype == VerusConstants.DEST_ID) && destinationAddress != address(0), "NFT packet wrong length/dest wrong");

            VerusNft nft = VerusNft(nftContract);
            require (nft.getApproved(tokenId) == address(this), "NFT not approved");

            nft.transferFrom(msg.sender, address(this), tokenId);
            
            if(transfer.currencyvalue.currency == VerusConstants.VerusNFTID)
            {
                nft.burn(tokenId);
            }

            transfer.destination.destinationtype = desttype;
            transfer.destination.destinationaddress = abi.encodePacked(destinationAddress);
 
        } 
        _createExports(transfer, false);
    }

    function exportERC20Tokens(uint256 _tokenAmount, Token token, bool burn, address sender ) private {
        
        (bool success, ) = address(token).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", sender, address(this), _tokenAmount));
        require(success, "transferfrom of token failed");

        if (burn) 
        {
            token.burn(_tokenAmount);
        }
    }

    function externalCreateExportCall(bytes memory data) public {

        (VerusObjects.CReserveTransfer memory reserveTransfer, bool forceNewCCE) = abi.decode(data, (VerusObjects.CReserveTransfer, bool));

        _createExports(reserveTransfer, forceNewCCE);
    }

    function _createExports(VerusObjects.CReserveTransfer memory reserveTransfer, bool forceNewCCE) private {

        // Create CCE: If transactions in transfers > 50 and on same block then revert.
        // If transactions over 50 and inbetween notarization boundaries, increment CCE start and endheight
        // If notarization happens increment CCE to next boundary
        // If changing from pool closed to pool open create a boundary (As all sends will then go through the bridge)
        uint64 blockNumber = uint64(block.number);
        uint64 notaryHeight = notaryHeight;
        uint64 cceStartHeight = cceLastStartHeight;
        uint64 cceEndHeight = cceLastEndHeight;
        uint64 lastCCEExportHeight = cceLastStartHeight;
        uint64 blockDelta = cceEndHeight - (cceStartHeight == 0 ? cceEndHeight : cceStartHeight);


        VerusObjects.CReserveTransferSet memory temptx = _readyExports[cceStartHeight];

        // if there are no transfers then there is no need to make a new CCE as this is the first one, and the endheight can become the block number if it is less than the current block no.
        // if the last notary received height is less than the endheight then keep building up the CCE (as long as 10 ETH blocks havent passed, and anew CCE isnt being forced and there is less than 50)

        if ((temptx.transfers.length < 1 || (notaryHeight < cceEndHeight && blockDelta < 10)) && !forceNewCCE  && temptx.transfers.length < 50) {

            // set the end height of the CCE to the current block.number only if the current block we are on is greater than its value
            if (cceEndHeight < blockNumber) {
                cceEndHeight = blockNumber;
            }
        // if a new CCE is triggered for any reason, its startblock is always the previous endblock +1, 
        // its start height may of spilled in to virtual future block numbers so if the current cce start height is less than the block we are on we can update the end 
        // height to a new greater value.  Otherwise if the startheight is still in the future then the endheight is also in the future at the same block.
        } else {
            cceStartHeight = cceEndHeight + 1;

            if (cceStartHeight < blockNumber) {
                cceEndHeight = blockNumber;
            } else {
                cceEndHeight = cceStartHeight;
            }
        }

        setReadyExportTransfers(cceStartHeight, cceEndHeight, reserveTransfer, 50);

        VerusObjects.CReserveTransferSet memory pendingTransfers = _readyExports[cceStartHeight];

        address crossChainExportAddress = mapper.getLogicContract(uint(VerusConstants.ContractType.VerusCrossChainExport));

        (bool success, bytes memory serializedCCE) = crossChainExportAddress.call(abi.encodeWithSignature("generateCCE(bytes)", abi.encode(pendingTransfers.transfers, poolAvailable, cceStartHeight, cceEndHeight)));
        require(success);

     //   bytes memory serializedCCE = verusCCE.generateCCE(pendingTransfers.transfers, poolAvailable, cceStartHeight, cceEndHeight);
        bytes32 prevHash;
 
        if(pendingTransfers.transfers.length == 1)
        {
            prevHash = _readyExports[lastCCEExportHeight].exportHash;
            cceLastStartHeight = cceStartHeight;
            cceLastEndHeight = cceEndHeight;
        } 
        else 
        {
            prevHash = pendingTransfers.prevExportHash;
        }
          
        setReadyExportTxid(keccak256(abi.encodePacked(serializedCCE, prevHash)), prevHash, cceStartHeight);

    }

    function setReadyExportTxid(bytes32 txidhash, bytes32 prevTxidHash, uint _block) private {
        
        _readyExports[_block].exportHash = txidhash;

        if (_readyExports[_block].transfers.length == 1)
        {
            _readyExports[_block].prevExportHash = prevTxidHash;

        }
    }

    function setReadyExportTransfers(uint64 _startHeight, uint64 _endHeight, VerusObjects.CReserveTransfer memory reserveTransfer, uint blockTxLimit) private {
        
        _readyExports[_startHeight].endHeight = _endHeight;
        _readyExports[_startHeight].transfers.push(reserveTransfer);
        require(_readyExports[_startHeight].transfers.length <= blockTxLimit);
      
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

//Second contract

contract SubmitImport is VerusStorage {
    function sendToVRSC(uint64 value, address sendTo, uint8 destinationType) public 
    {
        VerusObjects.CReserveTransfer memory LPtransfer;
        bool forceNewCCE;
      
        LPtransfer.version = 1;
        LPtransfer.destination.destinationtype = destinationType;
        LPtransfer.destcurrencyid = VerusConstants.VerusBridgeAddress;
        LPtransfer.destsystemid = address(0);
        LPtransfer.secondreserveid = address(0);

        LPtransfer.flags = VerusConstants.VALID;

        if (sendTo == address(0)) {
            LPtransfer.flags += VerusConstants.BURN_CHANGE_PRICE ;
            LPtransfer.destination.destinationaddress = bytes(hex'B26820ee0C9b1276Aac834Cf457026a575dfCe84');
        } else {
            LPtransfer.destination.destinationaddress = abi.encodePacked(sendTo);
        }
        
        if (value == 0) {
            LPtransfer.currencyvalue.currency = VerusConstants.VerusCurrencyId;
            LPtransfer.fees = VerusConstants.verusTransactionFee; 
            LPtransfer.feecurrencyid = VerusConstants.VerusCurrencyId;
            LPtransfer.currencyvalue.amount = uint64(poolSize - VerusConstants.verusTransactionFee);
            forceNewCCE = true;
        } else {
            LPtransfer.currencyvalue.currency = VerusConstants.VEth;
            LPtransfer.fees = VerusConstants.verusvETHTransactionFee; 
            LPtransfer.feecurrencyid = VerusConstants.VEth;
            LPtransfer.currencyvalue.amount = uint64(value - VerusConstants.verusvETHTransactionFee);  
            forceNewCCE = false;
        } 

        // When the bridge launches to make sure a fresh block with no pending vrsc transfers is used as not to mix destination currencies.
        address verusBridgeAddress = mapper.getLogicContract(uint(VerusConstants.ContractType.VerusBridge));

        (bool success,) = verusBridgeAddress.delegatecall(abi.encodeWithSignature("externalCreateExportCall(bytes,bool)", abi.encode(LPtransfer, forceNewCCE)));
        require(success);
       // _createExports(LPtransfer, true, forceNewCCE);

    }

    function _createImports(bytes calldata data) external returns(uint64) {
        
        
        VerusObjects.CReserveTransferImport memory _import = abi.decode(data, (VerusObjects.CReserveTransferImport));
        bytes32 txidfound;
        bytes memory elVchObj = _import.partialtransactionproof.components[0].elVchObj;
        uint32 nVins;
        bool success;
        bytes memory returnBytes;

        assembly 
        {
            txidfound := mload(add(elVchObj, 32)) 
            nVins := mload(add(elVchObj, 45)) 
        }
        
        // reverse 32bit endianess
        nVins = ((nVins & 0xFF00FF00) >> 8) |  ((nVins & 0x00FF00FF) << 8);
        nVins = (nVins >> 16) | (nVins << 16);

        if (processedTxids[txidfound]) 
        {
            revert("Known txid");
        } 

        bytes32 hashOfTransfers;

        // [0..139]address of reward recipricent and [140..203]int64 fees
        uint64 fees;

        // [0..31]startheight [32..63]endheight [64..95]nIndex, [96..128] numberoftransfers packed into a uint128  
        uint128 CCEHeightsAndnIndex;

        hashOfTransfers = keccak256(_import.serializedTransfers);

        address verusProofAddress = mapper.getLogicContract(uint(VerusConstants.ContractType.VerusProof));

        (success, returnBytes) = verusProofAddress.call(abi.encodeWithSignature("proveImports(bytes)", abi.encode(data, hashOfTransfers)));
        require(success);

        (fees, CCEHeightsAndnIndex) = abi.decode(returnBytes, (uint64, uint128));// verusProof.proveImports(_import, hashOfTransfers); 

        isLastCCEInOrder(uint32(CCEHeightsAndnIndex));
   
        // clear 4 bytes above first 64 bits, i.e. clear the nIndex 32 bit number, then convert to correct nIndex

        CCEHeightsAndnIndex  = (CCEHeightsAndnIndex & 0xffffffff00000000ffffffffffffffff) | (uint128(uint32(uint32(CCEHeightsAndnIndex >> 64) - (1 + (2 * nVins)))) << 64);  
        setLastImport(txidfound, hashOfTransfers, CCEHeightsAndnIndex);
        
        // Deserialize transfers and pack into send arrays, also pass in no. of transfers to calculate array size

        VerusObjects.ETHPayments[] memory _payments;
        
        address verusTokenManagerAddress = mapper.getLogicContract(uint(VerusConstants.ContractType.TokenManager));

        (success, returnBytes) = verusTokenManagerAddress.call(abi.encodeWithSignature("processTransactions(bytes,uint8)", _import.serializedTransfers, uint8(CCEHeightsAndnIndex >> 96)));
        require(success);

        bytes memory refunds;
        (_payments, refunds) = abi.decode(returnBytes, (VerusObjects.ETHPayments[], bytes)); //tokenManager.processTransactions(_import.serializedTransfers, uint8(CCEHeightsAndnIndex >> 96));
        
        sendEth(_payments);
        refund(refunds);

        return fees;

    }

    function sendEth(VerusObjects.ETHPayments[] memory _payments) private
    {
         //only callable by verusbridge contract

        uint256 totalsent;
        for(uint i = 0; i < _payments.length; i++)
        {
            address payable destination = payable(_payments[i].destination);
            if(destination != address(0))
            {
                destination.transfer(_payments[i].amount);
                totalsent += _payments[i].amount;
            }
        }
    }
    
    function refund(bytes memory refundAmount) private  {

        for(uint i = 0; i < (refundAmount.length / 64); i = i + 64) {

            bytes32 verusAddress;
            uint256 amount;
            assembly 
            {
                verusAddress := mload(add(add(refundAmount, 32), i))
                amount := mload(add(add(refundAmount, 64), i))
            }
            refunds[verusAddress] += amount; //verusNotarizerStorage.setOrAppendRefund(verusAddress, amount);
        }
     }

    function setLastImport(bytes32 processedTXID, bytes32 hashofTXs, uint128 CCEheightsandTXNum ) private {

        processedTxids[processedTXID] = true;
        lastTxIdImport = processedTXID;
        lastImportInfo[processedTXID] = VerusObjects.lastImportInfo(hashofTXs, processedTXID, uint32(CCEheightsandTXNum >> 64), uint32(CCEheightsandTXNum >> 32));
    } 

    function isLastCCEInOrder(uint32 height) private view {
      
        if ((lastImportInfo[lastTxIdImport].height + 1) == height)
        {
            return;
        } 
        else if (lastTxIdImport == bytes32(0))
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

            heights = exportHeights[heights];
            outputSize++;
            if (heights > _endBlock || heights == 0) {
                break;
            }
        }

        returnedExports = new VerusObjects.CReserveTransferSetCalled[](outputSize);
        VerusObjects.CReserveTransferSet memory tempSet;
        heights = _startBlock;

        for (uint i = 0; i < outputSize; i++)
        {
            tempSet = _readyExports[heights];
            returnedExports[i] = VerusObjects.CReserveTransferSetCalled(tempSet.exportHash, tempSet.prevExportHash, uint64(heights), tempSet.endHeight, tempSet.transfers);
            heights = exportHeights[heights];
        }
        return returnedExports;      
    }

    function setClaimableFees(uint64 fees) external
    {
        uint176 bridgeKeeper;
        bridgeKeeper = uint176(uint160(msg.sender));
        bridgeKeeper |= (uint176(0x0c14) << 160); //make ETH type '0c' and length 20 '14'

        uint256 notaryFees;
        uint256 LPFee;
        uint256 proposerFees;  
        uint256 bridgekeeperFees;              
        uint176 proposer;
        bytes memory proposerBytes = bestForks[0];

        assembly {
                proposer := mload(add(proposerBytes, 128))
        } 

        (notaryFees, proposerFees, bridgekeeperFees, LPFee) = setFeePercentages(fees);

        // Any remainder from Notaries shared fees is put into the LPFees pot.
        LPFee += setNotaryFees(notaryFees);

        setClaimedFees(bytes32(uint256(proposer)), proposerFees);
        setClaimedFees(bytes32(uint256(bridgeKeeper)), bridgekeeperFees);

        //NOTE: LP fees to be sent to vrsc to be burnt held at the verusNotarizerStorage address as a unique key
        uint256 totalLPFees = setClaimedFees(bytes32(uint256(uint160(address(this)))), LPFee);
        
        //NOTE:only execute the LP transfer if there is x10 the fee amount 
        if(totalLPFees > (VerusConstants.verusvETHTransactionFee * 10) && poolAvailable)
        {
            //make a transfer for the LP fees back to Verus
            sendToVRSC(uint64(totalLPFees), address(0), VerusConstants.DEST_PKH);
            setClaimableFees(bytes32(uint256(uint160(address(this)))), 0);
        }
    }

    function setFeePercentages(uint256 _ethAmount)private pure returns (uint256,uint256,uint256,uint256)
    {
        uint256 notaryFees;
        uint256 LPFees;
        uint256 proposerFees;  
        uint256 bridgekeeperFees;     
        
        notaryFees = (_ethAmount / 4 ); 
        proposerFees = _ethAmount / 4 ;
        bridgekeeperFees = (_ethAmount / 4 );

        LPFees = _ethAmount - (notaryFees + proposerFees + bridgekeeperFees);

        return(notaryFees, proposerFees, bridgekeeperFees, LPFees);
    }

    function setNotaryFees(uint256 notaryFees) private returns (uint64 remainder){  //sent in as SATS
      
        uint256 numOfNotaries = notaries.length;
        uint64 notariesShare = uint64(notaryFees / numOfNotaries);
        for (uint i=0; i < numOfNotaries; i++)
        {
            uint176 notary;
            notary = uint176(uint160(notaryAddressMapping[notaries[i]].main));
            notary |= (uint176(0x0c14) << 160); //set at type eth
            claimableFees[bytes32(uint256(notary))] += notariesShare;
        }
        remainder = uint64(notaryFees % numOfNotaries);
    }

    function setClaimedFees(bytes32 _address, uint256 fees) private returns (uint256)
    {
        claimableFees[_address] += fees;
        return claimableFees[_address];
    }

    function setClaimableFees(bytes32 claiment, uint256 fee) private {

        claimableFees[claiment] = fee;
    }

}