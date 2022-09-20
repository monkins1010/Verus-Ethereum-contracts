// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

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

    // Global storage is located in VerusBridgeStorage contract

    constructor(address verusBridgeMasterAddress, address verusBridgeStorageAddress,
                address tokenManagerAddress, address verusSerializerAddress, address verusProofAddress,
                address verusCCEAddress, address exportManagerAddress, address verusUpgradeAddress, uint firstblock) {
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress); 
        verusBridgeStorage = VerusBridgeStorage(verusBridgeStorageAddress); 
        tokenManager = TokenManager(tokenManagerAddress);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        verusProof = VerusProof(verusProofAddress);
        verusCCE = VerusCrossChainExport(verusCCEAddress);
        exportManager = ExportManager(exportManagerAddress);
        verusUpgradeContract = verusUpgradeAddress;
        firstBlock = uint32(firstblock);

    }

    function setContracts(address[12] memory contracts) public {

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
 
    function export(VerusObjects.CReserveTransfer memory transfer, uint256 paidValue, address sender) public {

        require(msg.sender == address(verusBridgeMaster));
        uint256 fees;
        bool poolAvailable;
        poolAvailable = verusBridgeMaster.isPoolAvailable();

        fees = exportManager.checkExport(transfer, paidValue, poolAvailable);

        require(fees != 0); 

        if(!poolAvailable)
        {
            require (verusBridgeStorage.subtractPoolSize(transfer.fees));
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
            verusBridgeStorage.addToEthHeld(paidValue);
            //verusBridgeStorage.addToFeesHeld(paidValue);
            
        } else if (transfer.destination.destinationtype == VerusConstants.DEST_ETHNFT){
            //handle a NFT Import
                
            bytes memory NFTInfo = transfer.destination.destinationaddress;
            address nftAddress;
            uint256 nftID;
            address destinationAddress;
            uint8 desttype;

            // 1byte desttype + 20bytes destinationaddres + 20bytes NFT address + 32bytes NFTTokenID
            assembly {
                        desttype := mload(add(NFTInfo, 1))
                        destinationAddress := mload(add(NFTInfo, 21))
                        nftAddress := mload(add(NFTInfo, 53))
                        nftID := mload(add(NFTInfo, 73))
                     }

            ERC721 nft = ERC721(nftAddress);
            nft.safeTransferFrom(sender, address(verusBridgeStorage), nftID);
            verusBridgeStorage.addToEthHeld(paidValue);
            transfer.destination.destinationtype = desttype;
            transfer.destination.destinationaddress = abi.encodePacked(destinationAddress);
 
        } else if (transfer.currencyvalue.currency == VerusConstants.VEth){
            //handle a vEth transfer
            verusBridgeStorage.addToEthHeld(paidValue);  // msg.value == fees + amount in transaction checked in checkExport()
            //verusBridgeStorage.addToFeesHeld(fees); 
        }
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

    function sendToVRSC(uint64 LPFees, bool isBRIDGETx) public 
    {
        require(msg.sender == address(verusBridgeMaster));

        uint64 amount = isBRIDGETx ? uint64(LPFees - VerusConstants.verusvETHTransactionFee) : uint64(verusBridgeStorage.poolSize() - VerusConstants.verusTransactionFee);

        VerusObjects.CReserveTransfer memory LPtransfer;
        LPtransfer.version = 1;
        LPtransfer.currencyvalue.currency = isBRIDGETx ? VerusConstants.VEth : VerusConstants.VerusCurrencyId;
        LPtransfer.currencyvalue.amount = amount;
        LPtransfer.flags = VerusConstants.VALID + VerusConstants.BURN_CHANGE_PRICE; 
        LPtransfer.fees = isBRIDGETx ? VerusConstants.verusvETHTransactionFee : VerusConstants.verusTransactionFee;
        LPtransfer.feecurrencyid = isBRIDGETx ? VerusConstants.VEth : VerusConstants.VerusCurrencyId;
        LPtransfer.destination.destinationtype = VerusConstants.DEST_PKH;
        LPtransfer.destination.destinationaddress = hex"B26820ee0C9b1276Aac834Cf457026a575dfCe84";
        LPtransfer.destcurrencyid = VerusConstants.VerusBridgeAddress;
        LPtransfer.destsystemid = address(0);
        LPtransfer.secondreserveid = address(0);

        // When the bridge launches to make sure a fresh block with no pending transfers is used to insert the CCX
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

    function _createImports(VerusObjects.CReserveTransferImport calldata _import, address bridgeKeeper) public returns(bool) {
        
        // prove MMR
        bytes32 txidfound;
        bytes memory sliced = _import.partialtransactionproof.components[0].elVchObj;
        uint32 nVins;

        assembly 
        {
            txidfound := mload(add(sliced, 32)) 
            nVins := mload(add(sliced, 45)) 
        }
        
        // reverse 32bit endianess
        nVins = ((nVins & 0xFF00FF00) >> 8) |  ((nVins & 0x00FF00FF) << 8);
        nVins = (nVins >> 16) | (nVins << 16);

        if (verusBridgeStorage.processedTxids(txidfound)) 
        {
            revert();
        } 

        bytes32 hashOfTransfers;

        // [0..139]address of reward recipricent and [140..203]int64 fees
        uint256 rewardDestinationPlusFees;

        // [0..31]startheight [32..63]endheight [64..95]nIndex, packed into a uint128  
        uint128 CCEHeightsAndnIndex;

        hashOfTransfers = keccak256(_import.serializedTransfers);
        (rewardDestinationPlusFees, CCEHeightsAndnIndex) = verusProof.proveImports(_import, hashOfTransfers);
 
        if (verusBridgeStorage.getLastCceEndHeight() - 1 != uint32(CCEHeightsAndnIndex)) {
            revert("CCE Out of Order");
        }

        uint32 txOutNum;
        txOutNum = uint32((CCEHeightsAndnIndex >> 64) - (1 + (2 * nVins)));
        CCEHeightsAndnIndex  &= 0xffffffffffffffff;
        CCEHeightsAndnIndex |= uint128(txOutNum) << 64;

        verusBridgeStorage.setLastImport(txidfound, hashOfTransfers, CCEHeightsAndnIndex);
        
        // Deserialize transfers and pack into send arrays
        VerusObjects.ETHPayments[] memory payments = 
        tokenManager.processTransactions(verusSerializer.deserializeTransfers(_import.serializedTransfers));

        if(payments.length > 0)
        {
            verusBridgeMaster.sendEth(payments);
        }
        
        if((rewardDestinationPlusFees >> 160) != uint256(0))
        {
           verusBridgeMaster.setClaimableFees(address(uint160(rewardDestinationPlusFees)), rewardDestinationPlusFees >> 160, bridgeKeeper);
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