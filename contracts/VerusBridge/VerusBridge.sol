// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "./TokenManager.sol";
import "./VerusBridgeMaster.sol";
import "./VerusBridgeStorage.sol";
import "../MMR/VerusProof.sol";
import "./Token.sol";
import "./VerusSerializer.sol";
import "./VerusCrossChainExport.sol";
import "./ExportManager.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract VerusBridge {

    TokenManager tokenManager;
    VerusSerializer verusSerializer;
    VerusProof verusProof;
    VerusCrossChainExport verusCCE;
    VerusBridgeMaster verusBridgeMaster;
    ExportManager exportManager;
    VerusBridgeStorage verusBridgeStorage;
    address verusUpgradeContract;

    uint32 public firstBlock;
    uint64 poolSize;  

    // Global storage is located in VerusBridgeStorage contract

    constructor(address verusBridgeMasterAddress, address verusBridgeStorageAddress,
                address tokenManagerAddress, address verusSerializerAddress, address verusProofAddress,
                address verusCCEAddress, address exportManagerAddress, address verusUpgradeAddress, uint firstblock, uint64 _poolSize) {
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress); 
        verusBridgeStorage = VerusBridgeStorage(verusBridgeStorageAddress); 
        tokenManager = TokenManager(tokenManagerAddress);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        verusProof = VerusProof(verusProofAddress);
        verusCCE = VerusCrossChainExport(verusCCEAddress);
        exportManager = ExportManager(exportManagerAddress);
        verusUpgradeContract = verusUpgradeAddress;
        firstBlock = uint32(firstblock);
        poolSize = _poolSize;

    }

    function setContracts(address[13] memory contracts) public {

        require(msg.sender == verusUpgradeContract);

        if(contracts[uint(VerusConstants.ContractType.TokenManager)] != address(tokenManager)) {
            tokenManager = TokenManager(contracts[uint(VerusConstants.ContractType.TokenManager)]);
        }
        
        if(contracts[uint(VerusConstants.ContractType.VerusSerializer)] != address(verusSerializer)) {
            verusSerializer = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]);
        }
        
        if(contracts[uint(VerusConstants.ContractType.VerusProof)] != address(verusProof))
            verusProof = VerusProof(contracts[uint(VerusConstants.ContractType.VerusProof)]);    

        if(contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)] != address(verusCCE))     
            verusCCE = VerusCrossChainExport(contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)]);

        if(contracts[uint(VerusConstants.ContractType.ExportManager)] != address(exportManager))     
            exportManager = ExportManager(contracts[uint(VerusConstants.ContractType.ExportManager)]);

    }

    function subtractPoolSize(uint64 _amount) private returns (bool) {

        if(_amount > poolSize) return false;
        poolSize -= _amount;
        return true;
    }
 
    function export(VerusObjects.CReserveTransfer memory transfer, uint256 paidValue, address sender) public {

        require(msg.sender == address(verusBridgeMaster));
        uint256 fees;
        bool poolAvailable;
        poolAvailable = verusBridgeMaster.isPoolAvailable();

        fees = exportManager.checkExport(transfer, paidValue, poolAvailable);

        require(fees != 0); 

        if(!poolAvailable)
        {
            require (subtractPoolSize(uint64(transfer.fees)));
        }

        if (transfer.currencyvalue.currency != VerusConstants.VEth && transfer.destination.destinationtype != VerusConstants.DEST_ETHNFT) {

            VerusObjects.mappedToken memory mappedContract = verusBridgeStorage.getERCMapping(transfer.currencyvalue.currency);
            Token token = Token(mappedContract.erc20ContractAddress); 
            //Check user has allowed the verusBridgeStorage contract to spend on their behalf
            uint256 allowedTokens = token.allowance(sender, address(verusBridgeStorage));
            uint256 tokenAmount = tokenManager.convertFromVerusNumber(transfer.currencyvalue.amount, token.decimals()); //convert to wei from verus satoshis
            require( allowedTokens >= tokenAmount);
            //transfer the tokens to the verusbridgemaster contract
            //total amount kept as wei until export to verus
            verusBridgeStorage.exportERC20Tokens(tokenAmount, token, mappedContract.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED, sender );
            
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
                nftContract := mload(add(serializedDest, 41))
                tokenId := mload(add(serializedDest, 73))
            }
            require (serializedDest.length == 73 && (desttype == VerusConstants.DEST_PKH || desttype == VerusConstants.DEST_ID), "NFT packet wrong length/dest wrong");

            ERC721 nft = ERC721(nftContract);
            require (nft.getApproved(tokenId) == address(this), "NFT not approved");

            nft.transferFrom(sender, address(this), tokenId);
            nft.transferFrom(address(this), address(verusBridgeStorage), tokenId);
            transfer.destination.destinationtype = desttype;
            transfer.destination.destinationaddress = abi.encodePacked(destinationAddress);
 
        } 
        verusBridgeMaster.addToEthHeld(paidValue); 
        _createExports(transfer, poolAvailable, block.number);
    }

    function _createExports(VerusObjects.CReserveTransfer memory newTransaction, bool poolAvailable, uint blockNumber) private {
        uint currentHeight = blockNumber;

        //check if the current block height has a set of transfers associated with it if so add to the existing array
        bool newBlock;
        newBlock = verusBridgeStorage.setReadyExportTransfers(currentHeight, newTransaction);

        bytes memory serializedCCE = verusSerializer.serializeCCrossChainExport(verusCCE.generateCCE(verusBridgeStorage.getReadyExports(currentHeight).transfers, poolAvailable, currentHeight));

        bytes32 prevHash;
 
        if(newBlock)
        {
            prevHash = verusBridgeStorage.getReadyExports(verusBridgeStorage.lastCCEExportHeight()).exportHash;
        } 
        else 
        {
            prevHash = verusBridgeStorage.getReadyExports(currentHeight).prevExportHash;
        }
          
        verusBridgeStorage.setReadyExportTxid(keccak256(abi.encodePacked(serializedCCE, prevHash)), prevHash, currentHeight);

    }

    function sendToVRSC(uint64 LPFees, bool isBRIDGETx, address sendTo) public 
    {
        require(msg.sender == address(verusBridgeMaster));

        uint64 amount = isBRIDGETx ? uint64(LPFees - VerusConstants.verusvETHTransactionFee) : uint64(poolSize - VerusConstants.verusTransactionFee);

        VerusObjects.CReserveTransfer memory LPtransfer;
        LPtransfer.version = 1;
        LPtransfer.currencyvalue.currency = isBRIDGETx ? VerusConstants.VEth : VerusConstants.VerusCurrencyId;
        LPtransfer.currencyvalue.amount = amount;
        LPtransfer.flags = sendTo == address(0) ? VerusConstants.VALID + VerusConstants.BURN_CHANGE_PRICE : VerusConstants.VALID; 
        LPtransfer.fees = isBRIDGETx ? VerusConstants.verusvETHTransactionFee : VerusConstants.verusTransactionFee;
        LPtransfer.feecurrencyid = isBRIDGETx ? VerusConstants.VEth : VerusConstants.VerusCurrencyId;
        LPtransfer.destination.destinationtype = VerusConstants.DEST_PKH;
        LPtransfer.destination.destinationaddress = sendTo == address(0) ? bytes(hex'B26820ee0C9b1276Aac834Cf457026a575dfCe84') : abi.encodePacked(sendTo);
        LPtransfer.destcurrencyid = VerusConstants.VerusBridgeAddress;
        LPtransfer.destsystemid = address(0);
        LPtransfer.secondreserveid = address(0);

        // When the bridge launches to make sure a fresh block with no pending transfers is used to insert the CCE
        _createExports(LPtransfer, true, block.number + 1);

    }

    /***
     * Import from Verus functions
     ***/
    function checkImports(bytes32[] memory _imports) public view returns(bytes32[] memory) {
        //loop through the transfers and return a list of unprocessed
        bytes32[] memory txidList = new bytes32[](_imports.length);
        uint iterator;
        for(uint i = 0; i < _imports.length; i++)
        {
            if(verusBridgeStorage.processedTxids(_imports[i]) != true)
            {
                txidList[iterator] = _imports[i];
                iterator++;
            }
        }
        return txidList;
    }

    function _createImports(VerusObjects.CReserveTransferImport calldata _import, uint176 bridgeKeeper) public returns(bool) {
        
        // prove MMR
        require(msg.sender == address(verusBridgeMaster));
        bytes32 txidfound;
        bytes memory elVchObj = _import.partialtransactionproof.components[0].elVchObj;
        uint32 nVins;

        assembly 
        {
            txidfound := mload(add(elVchObj, 32)) 
            nVins := mload(add(elVchObj, 45)) 
        }
        
        // reverse 32bit endianess
        nVins = ((nVins & 0xFF00FF00) >> 8) |  ((nVins & 0x00FF00FF) << 8);
        nVins = (nVins >> 16) | (nVins << 16);

        if (verusBridgeStorage.processedTxids(txidfound)) 
        {
            revert("Known txid");
        } 

        bytes32 hashOfTransfers;

        // [0..139]address of reward recipricent and [140..203]int64 fees
        uint256 rewardDestinationPlusFees;

        // [0..31]startheight [32..63]endheight [64..95]nIndex, [96..128] numberoftransfers packed into a uint128  
        uint128 CCEHeightsAndnIndex;

        hashOfTransfers = keccak256(_import.serializedTransfers);

        (rewardDestinationPlusFees, CCEHeightsAndnIndex) = verusProof.proveImports(_import, hashOfTransfers);
 
        verusBridgeStorage.isLastCCEInOrder(uint32(CCEHeightsAndnIndex));

        // clear 4 bytes above first 64 bits, i.e. clear the nIndex 32 bit number, then convert to correct nIndex

        CCEHeightsAndnIndex  = (CCEHeightsAndnIndex & 0xffffffff00000000ffffffffffffffff) | (uint128(uint32(uint32(CCEHeightsAndnIndex >> 64) - (1 + (2 * nVins)))) << 64);  
        verusBridgeStorage.setLastImport(txidfound, hashOfTransfers, CCEHeightsAndnIndex);
        
        // Deserialize transfers and pack into send arrays, also pass in no. of transfers to calculate array size
        verusBridgeMaster.sendEth(tokenManager.processTransactions(_import.serializedTransfers, uint8(CCEHeightsAndnIndex >> 96)));

        
        if(address(uint160(rewardDestinationPlusFees)) != address(0) && rewardDestinationPlusFees >> 176 != 0)
        {
           verusBridgeMaster.setClaimableFees(bytes32(uint256(uint176(rewardDestinationPlusFees))), rewardDestinationPlusFees >> 176, bridgeKeeper);
        }
        return true;
    }
    
    function getReadyExportsByRange(uint _startBlock,uint _endBlock) public view returns(VerusObjects.CReserveTransferSet[] memory returnedExports){
        //calculate the size that the return array will be to initialise it
        uint outputSize = 0;
        if (_startBlock < firstBlock) 
        {
            _startBlock = firstBlock;
        }

        for(uint i = _startBlock; i <= _endBlock; i++)
        {
            if (verusBridgeStorage.getReadyExports(i).exportHash != bytes32(0))  outputSize += 1;
        }

        VerusObjects.CReserveTransferSet[] memory output = new VerusObjects.CReserveTransferSet[](outputSize);
        uint outputPosition = 0;
        for (uint blockNumber = _startBlock; blockNumber <= _endBlock; blockNumber++)
        {
            if (verusBridgeStorage.getReadyExports(blockNumber).exportHash != bytes32(0)) 
            {
                output[outputPosition] = verusBridgeStorage.getReadyExports(blockNumber);
                outputPosition++;
            }
        }
        return output;      
    }


}