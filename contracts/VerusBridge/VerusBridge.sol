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

        assert(msg.sender == verusUpgradeContract);

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

        assert(msg.sender == address(verusBridgeMaster));
        uint256 fees;
        bool poolAvailable;
        poolAvailable = verusBridgeMaster.isPoolAvailable();

        fees = exportManager.checkExport(transfer, paidValue, poolAvailable);

        assert(fees != 0); 

        if(!poolAvailable)
        {
            assert (verusBridgeStorage.subtractPoolSize(tokenManager.convertFromVerusNumber(transfer.fees, 18)));
        }

        if (transfer.currencyvalue.currency != VerusConstants.VEth) {

            VerusObjects.mappedToken memory mappedContract = verusBridgeStorage.getERCMapping(transfer.currencyvalue.currency);
            Token token = Token(mappedContract.erc20ContractAddress); 
            //Check user has allowed the verusBridgeStorage contract to spend on their behalf
            uint256 allowedTokens = token.allowance(sender, address(verusBridgeStorage));
            uint256 tokenAmount = tokenManager.convertFromVerusNumber(transfer.currencyvalue.amount, token.decimals()); //convert to wei from verus satoshis
            assert( allowedTokens >= tokenAmount);
            //transfer the tokens to the verusbridgemaster contract
            //total amount kept as wei until export to verus
            verusBridgeStorage.exportERC20Tokens(tokenAmount, token, mappedContract.flags, sender );
            verusBridgeStorage.addToFeesHeld(paidValue);
            
        } else if (transfer.flags == VerusConstants.CURRENCY_EXPORT){
            //handle a NFT Import
            verusBridgeStorage.addToFeesHeld(paidValue);
    
            bytes memory NFTInfo = transfer.destination.destinationaddress;
            address NFTAddress;
            uint256 NFTID;
            assembly {
                        NFTAddress := mload(add(NFTInfo, 20))
                        NFTID := mload(add(NFTInfo, 52))
                     }

            ERC721 NFT = ERC721(NFTAddress);

            verusBridgeStorage.transferFromERC721(address(verusBridgeStorage), sender, NFT, NFTID );
 
        } else if (transfer.currencyvalue.currency == VerusConstants.VEth){
            //handle a vEth transfer
            transfer.currencyvalue.amount = uint64(tokenManager.convertToVerusNumber(paidValue - fees,18));
            verusBridgeStorage.addToEthHeld(paidValue - fees);  // msg.value == fees + amount in transaction checked in checkExport()
            verusBridgeStorage.addToFeesHeld(fees); 
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

    function submitImports(VerusObjects.CReserveTransferImport[] memory _imports) public {
        //loop through the transfers and process
        for(uint i = 0; i < _imports.length; i++){
           _createImports(_imports[i]);
        }
    }


    function _createImports(VerusObjects.CReserveTransferImport memory _import) public returns(bool) {

        bytes32 txidfound;
        bytes memory sliced = _import.partialtransactionproof.components[0].elVchObj;

        assembly {
            txidfound := mload(add(sliced, 32))                                 // skip memory length (ETH encoded in an efficient 32 bytes ;) )
        }
        if (verusBridgeStorage.processedTxids(txidfound) == true) return false; 

        bool proven = verusProof.proveImports(_import);

        assert(proven);
        verusBridgeStorage.setProcessedTxids(txidfound);

        if (verusBridgeStorage.lastTxImportHeight() < _import.height)
            verusBridgeStorage.setlastTxImportHeight(_import.height);

        uint256 amount; 

        // check the transfers were in the hash.
        for (uint i = 0; i < _import.transfers.length; i++){
            // handle eth transactions
            amount = tokenManager.convertFromVerusNumber(uint256(_import.transfers[i].currencyvalue.amount),18);

            // if the transfer does not have the EXPORT_CURRENCY flag set
            if (_import.transfers[i].flags & VerusConstants.CURRENCY_EXPORT != VerusConstants.CURRENCY_EXPORT){
                    address destinationAddress;

                    bytes memory tempAddress  = _import.transfers[i].destination.destinationaddress;

                    assembly {
                    destinationAddress := mload(add(tempAddress, 20))
                    } 

                if (destinationAddress != address(0)) {

                    if (_import.transfers[i].currencyvalue.currency == VerusConstants.VEth) {
                        // ETH is held in VerusBridgemaster
                        assert (amount <= address(verusBridgeMaster).balance);
                            verusBridgeMaster.sendEth(amount, payable(destinationAddress));
                            verusBridgeStorage.subtractFromEthHeld(amount);
                            
                
                    } else if(verusBridgeStorage.ERC20Registered(_import.transfers[i].currencyvalue.currency)){
                        // handle erc20 transactions  
                        // amount conversion is handled in token manager

                        tokenManager.importERC20Tokens(_import.transfers[i].currencyvalue.currency,
                            _import.transfers[i].currencyvalue.amount,
                            destinationAddress);
                    } else {
                        
                        uint256 NFTID; 
                        ERC721 NFT;    //TODO: get the NFT contract address and ID
                        if(NFTID != uint256(0))
                            verusBridgeStorage.transferFromERC721(destinationAddress, address(verusBridgeStorage), NFT, NFTID );

                    }
                }
            } else if (_import.transfers[i].destination.destinationtype & VerusConstants.DEST_REGISTERCURRENCY == VerusConstants.DEST_REGISTERCURRENCY) {
                     
                tokenManager.deployToken(_import.transfers[i].destination.destinationaddress);
                
            } else if (_import.transfers[i].destination.destinationtype == 0) {

            //TODO: Handle NFTS

            }

            if (_import.transfers[i].fees > 0 && _import.transfers[i].feecurrencyid == VerusConstants.VEth)
            {



            }
        }

        address rewardDestination;
        bytes memory destHex = _import.exportinfo.rewardaddress.destinationaddress;
        assembly 
        {
            rewardDestination := mload(add(destHex , 20))
        }

        if(_import.exportinfo.totalfees[0].currency == VerusConstants.VEth)
        {
            verusBridgeMaster.setClaimableFees(rewardDestination, _import.exportinfo.totalfees[0].amount);
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
