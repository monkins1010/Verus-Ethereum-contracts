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

    // Global storage is located in VerusBridgeStorage contract

    constructor(address verusBridgeMasterAddress, address verusBridgeStorageAddress,
                address tokenManagerAddress, address verusSerializerAddress, address verusProofAddress,
                address verusCCEAddress, address exportManagerAddress, address verusUpgradeAddress) {
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress); 
        verusBridgeStorage = VerusBridgeStorage(verusBridgeStorageAddress); 
        tokenManager = TokenManager(tokenManagerAddress);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        verusProof = VerusProof(verusProofAddress);
        verusCCE = VerusCrossChainExport(verusCCEAddress);
        exportManager = ExportManager(exportManagerAddress);
        verusUpgradeContract = verusUpgradeAddress;

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
            require (verusBridgeStorage.subtractPoolSize(tokenManager.convertFromVerusNumber(transfer.fees, 18)));
        }

        if (transfer.currencyvalue.currency != VerusConstants.VEth) {

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
            
        } else if (transfer.flags == VerusConstants.CURRENCY_EXPORT){
            //handle a NFT Import
                
            bytes memory NFTInfo = transfer.destination.destinationaddress;
            address NFTAddress;
            uint256 NFTID;
            assembly {
                        NFTAddress := mload(add(NFTInfo, 20))
                        NFTID := mload(add(NFTInfo, 52))
                     }

          //  ERC721 NFT = ERC721(NFTAddress);

           //TODO: add verusBridgeStorage.transferFromERC721(address(verusBridgeStorage), sender, NFT, NFTID );
            verusBridgeStorage.addToEthHeld(paidValue);
 
        } else if (transfer.currencyvalue.currency == VerusConstants.VEth){
            //handle a vEth transfer
            verusBridgeStorage.addToEthHeld(paidValue);  // msg.value == fees + amount in transaction checked in checkExport()
            //verusBridgeStorage.addToFeesHeld(fees); 
        }
        _createExports(transfer, poolAvailable);
    }

    function _createExports(VerusObjects.CReserveTransfer memory newTransaction, bool poolAvailable) private {
        uint currentHeight = block.number;

        //check if the current block height has a set of transfers associated with it if so add to the existing array
        bool newBlock;
        newBlock = verusBridgeStorage.setReadyExportTransfers(currentHeight, newTransaction);

        bytes memory serializedCCE = verusSerializer.serializeCCrossChainExport(verusCCE.generateCCE(verusBridgeStorage.getReadyExports(currentHeight).transfers, poolAvailable));

        bytes32 prevHash;
 
        if(newBlock)
        {
            prevHash = verusBridgeStorage.getReadyExports(verusBridgeStorage.lastCCEExportHeight()).exportHash;
        } 
        else 
        {
            prevHash = verusBridgeStorage.getReadyExports(currentHeight).prevExportHash;
        }
          
        verusBridgeStorage.setReadyExportTxid(keccak256(abi.encodePacked(serializedCCE, prevHash)), prevHash);

    }

    /***
     * Import from Verus functions
     ***/
    function checkImports(bytes32[] memory _imports) public view returns(bytes32[] memory) {
        //loop through the transfers and return a list of unprocessed
        bytes32[] memory txidList = new bytes32[](_imports.length);
        uint iterator;
        for(uint i = 0; i < _imports.length; i++){
            if(verusBridgeStorage.processedTxids(_imports[i]) != true){
                txidList[iterator] = _imports[i];
                iterator++;
            }
        }
        return txidList;
    }

    function submitImports(VerusObjects.CReserveTransferImport[] calldata _imports) public {
        //loop through the transfers and process
        for(uint i = 0; i < _imports.length; i++){
           _createImports(_imports[i]);
        }
    }


    function _createImports(VerusObjects.CReserveTransferImport calldata _import) public returns(bool) {
        
        // prove MMR
        bytes32 txidfound;
        bytes memory sliced = _import.partialtransactionproof.components[0].elVchObj;

        assembly {
            txidfound := mload(add(sliced, 32)) 
        }
       //REMOVE COMMENT if (verusBridgeStorage.processedTxids(txidfound) == true) {return false}; 

        bool proven = verusProof.proveImports(_import);

        require(!proven);
        verusBridgeStorage.setProcessedTxids(txidfound);

        if (verusBridgeStorage.lastTxImportHeight() < _import.height)
            verusBridgeStorage.setlastTxImportHeight(_import.height);
       
        // Deserialize transfers and pack into send arrays

        VerusObjects.ETHPayments[] memory payments = 
        tokenManager.processTransactions(verusSerializer.deserializeTransfers(_import.serializedTransfers));

        if(payments.length > 0)
            verusBridgeMaster.sendEth(payments);

        address rewardDestination;
        bytes memory destHex = _import.exportinfo.rewardaddress.destinationaddress;
        assembly 
        {
            rewardDestination := mload(add(destHex , 20))
        }

        if(_import.exportinfo.totalfees[0].currency == VerusConstants.VEth)
        {
           // verusBridgeMaster.setClaimableFees(rewardDestination, _import.exportinfo.totalfees[0].amount);
        }
        return true;
    }
    
    function getReadyExportsByRange(uint _startBlock,uint _endBlock) public view returns(VerusObjects.CReserveTransferSet[] memory returnedExports){
        //calculate the size that the return array will be to initialise it
        uint outputSize = 0;
        if(_startBlock < verusBridgeStorage.firstBlock()) _startBlock = verusBridgeStorage.firstBlock();
        for(uint i = _startBlock; i <= _endBlock; i++){
            if(verusBridgeStorage.getReadyExports(i).exportHash != bytes32(0))  outputSize += 1;
        }

        VerusObjects.CReserveTransferSet[] memory output = new VerusObjects.CReserveTransferSet[](outputSize);
        uint outputPosition = 0;
        for (uint blockNumber = _startBlock; blockNumber <= _endBlock; blockNumber++){
            if (verusBridgeStorage.getReadyExports(blockNumber).exportHash != bytes32(0)) {
                output[outputPosition] = verusBridgeStorage.getReadyExports(blockNumber);
                outputPosition++;
            }
        }
        return output;      
    }


}
