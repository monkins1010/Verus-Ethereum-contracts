// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "./TokenManager.sol";
import "./VerusBridgeMaster.sol";
import "../MMR/VerusProof.sol";
import "./Token.sol";
import "./VerusSerializer.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusCrossChainExport.sol";

contract VerusBridge {

    //list of erc20 tokens that can be accessed,
    //the contract must be able to mint and burn coins on the contract
    //defines the tokenManager which creates the erc20
    TokenManager tokenManager;
    VerusSerializer verusSerializer;
    VerusProof verusProof;
    VerusNotarizer verusNotarizer;
    VerusCrossChainExport verusCCE;
    VerusBridgeMaster verusBridgeMaster;

    // THE CONTRACT OWNER NEEDS TO BE REPLACED BY A SET OF NOTARIES
    address contractOwner;

    bool public deprecated = false;     // indicates if the contract is deprecated
    address public upgradedAddress;     // new contract, if this is deprecated

    uint public firstBlock = 0;

    // used to prove the transfers the index of this corresponds to the index of the 
    bytes32[] public readyExportHashes;

    // DO NOT ADD ANY VARIABLES ABOVE THIS POINT
    // used to store a list of currencies and an amount
    VerusObjects.CReserveTransfer[] private _pendingExports;
    
    // stores the blockheight of each pending transfer
    // the export set holds the summary of a set of exports
    VerusObjects.CReserveTransfer[][] public _readyExports;
    
    //stores the index corresponds to the block
    VerusObjects.LastImport public lastimport;
    mapping (bytes32 => bool) public processedTxids;
    mapping (uint => VerusObjects.blockCreated) public readyExportsByBlock;
    
    uint public lastTxImportHeight;

    uint32 constant CTRX_CURRENCY_EXPORT_FLAG = 0x2000;
    uint8 constant DEST_REGISTERCURRENCY = 6;
    
    constructor(address verusBridgeMasterAddress) {
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress); 
        lastimport.height = 0;
        lastimport.txid = 0x00000000000000000000000000000000;
    }

 
    function export(VerusObjects.CReserveTransfer memory transfer, uint256 paidValue) public payable {
        uint256 requiredFees =  VerusConstants.transactionFee;
        uint256 verusFees = VerusConstants.verusTransactionFee;
        tokenManager = TokenManager(verusBridgeMaster.getContractAddress(VerusBridgeMaster.ContractType.TokenManager));

        //TODO: We cant mix different transfer destinations together in the CCE assert on non same fields.
        if (readyExportsByBlock[block.number].created)
        {
            uint exportIndex = readyExportsByBlock[block.number].index;

            // QUESTION: what about reserve transfers that are import to source?
            assert( _readyExports[exportIndex][0].destcurrencyid == transfer.destcurrencyid);
        }

        //if there is fees in the pool spend those and not the amount that
        if (verusBridgeMaster.isPoolAvailable(transfer.fees,transfer.feecurrencyid)) {
            verusBridgeMaster.setPoolSize(verusBridgeMaster.getPoolSize() - VerusConstants.verusTransactionFee);
        } else {
            //if fees are being paid in verustest we need to take it from the msg sender
            assert(transfer.feecurrencyid == VerusConstants.VerusCurrencyId || transfer.feecurrencyid == VerusConstants.VEth);
            if(transfer.feecurrencyid == VerusConstants.VerusCurrencyId) {
                
                //burn the required amount of vrsctest from the user
                Token token = tokenManager.getTokenERC20(transfer.feecurrencyid);
                uint256 VRSTallowedTokens = token.allowance(msg.sender, address(this));
                assert( VRSTallowedTokens >= verusBridgeMaster.convertFromVerusNumber(verusFees,18));
                token.transferFrom(msg.sender,address(this), verusBridgeMaster.convertFromVerusNumber(verusFees,18)); 
                //transfer the tokens to this contract
                token.burn(verusFees); 

            } else if(transfer.feecurrencyid == VerusConstants.VEth){
                requiredFees = requiredFees * 3;
                assert(paidValue >= requiredFees + verusBridgeMaster.convertFromVerusNumber(transfer.fees,18));    
            }
            //if the fees are being paid in veth then require the user to send it
            //fees need to be paid for verus as well
        }

        if (transfer.currencyvalue.currency != VerusConstants.VEth) {
            //check there are enough fees sent
            verusBridgeMaster.setFeesHeld(verusBridgeMaster.getFeesHeld() + paidValue);
            //check that the token is registered
            Token token = tokenManager.getTokenERC20(transfer.currencyvalue.currency);
            uint256 allowedTokens = token.allowance(msg.sender,address(this));
            uint256 tokenAmount = verusBridgeMaster.convertFromVerusNumber(transfer.currencyvalue.amount,token.decimals()); //convert to wei from verus satoshis
            assert( allowedTokens >= tokenAmount);
            //transfer the tokens to this contract
            token.transferFrom(msg.sender,address(this),tokenAmount); 
            token.approve(address(tokenManager),tokenAmount);
            //give an approval for the tokenmanagerinstance to spend the tokens
            tokenManager.exportERC20Tokens(address(token), tokenAmount);  //total amount kept as wei until export to verus
        } else {
            //handle a vEth transfer
            transfer.currencyvalue.amount = uint64(verusBridgeMaster.convertToVerusNumber(paidValue - VerusConstants.transactionFee,18));
            verusBridgeMaster.setEthHeld(verusBridgeMaster.getEthHeld() + transfer.currencyvalue.amount);  
            verusBridgeMaster.setFeesHeld(verusBridgeMaster.getFeesHeld() + VerusConstants.transactionFee);
        }
        _createExports(transfer);
    }

    function _createExports(VerusObjects.CReserveTransfer memory newTransaction) private {
        uint currentHeight = block.number;
        uint exportIndex;
        bool newHash;
        verusSerializer = VerusSerializer(verusBridgeMaster.getContractAddress(VerusBridgeMaster.ContractType.VerusSerializer));
        verusNotarizer = VerusNotarizer(verusBridgeMaster.getContractAddress(VerusBridgeMaster.ContractType.VerusNotarizer));
        verusCCE = VerusCrossChainExport(verusBridgeMaster.getContractAddress(VerusBridgeMaster.ContractType.VerusCrossChainExport));
        //check if the current block height has a set of transfers associated with it if so add to the existing array
        if (readyExportsByBlock[currentHeight].created) {
            //append to an existing array of transfers
            exportIndex = readyExportsByBlock[currentHeight].index;
            _readyExports[exportIndex].push(newTransaction);
            newHash = false;
        }
        else {
            _pendingExports.push(newTransaction);
            exportIndex = _readyExports.length;
            _readyExports.push(_pendingExports);
            readyExportsByBlock[currentHeight] = VerusObjects.blockCreated(exportIndex, true);
            delete _pendingExports;
            newHash = true;
        }
       
        // QUESTION: why such a complicated test to determine destination currency on Verus?
        // likely better would be to have a bool of bridge ready
        bool bridgeReady = (0 < verusNotarizer.poolAvailable(VerusConstants.VerusBridgeAddress) &&
            verusNotarizer.poolAvailable(VerusConstants.VerusBridgeAddress) < uint32(block.number));

        bytes memory serializedCCE = verusSerializer.serializeCCrossChainExport(verusCCE.generateCCE(_readyExports[exportIndex], bridgeReady));

        bytes32 hashedCCE;
        bytes32 lastCCEHash = 0;
        if (exportIndex != 0) lastCCEHash = readyExportHashes[exportIndex -1];
        hashedCCE = keccak256(abi.encodePacked(serializedCCE, lastCCEHash));

        //add the hashed value
        if (newHash) readyExportHashes.push(hashedCCE);
        else readyExportHashes[exportIndex] = hashedCCE;

        if (firstBlock == 0) firstBlock = currentHeight;
    }

    function getlastimportheight() public view returns(uint) {
        return lastTxImportHeight;
    }

    /***
     * Import from Verus functions
     ***/
    function checkImports(bytes32[] memory _imports) public view returns(bytes32[] memory) {
        //loop through the transfers and return a list of unprocessed
        bytes32[] memory txidList = new bytes32[](_imports.length);
        uint iterator;
        for(uint i = 0; i < _imports.length; i++){
            if(processedTxids[_imports[i]] != true){
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
        verusProof =  VerusProof(verusBridgeMaster.getContractAddress(VerusBridgeMaster.ContractType.VerusProof));
        assembly {
            txidfound := mload(add(sliced, 32))                                 // skip memory length (ETH encoded in an efficient 32 bytes ;) )
        }
        if (processedTxids[txidfound] == true) return false; 

        bool proven = verusProof.proveImports(_import);

        assert(proven);
        processedTxids[txidfound] = true;

        if (lastTxImportHeight < _import.height)
            lastTxImportHeight = _import.height;

        uint256 amount;

        // check the transfers were in the hash.
        for(uint i = 0; i < _import.transfers.length; i++){
            // handle eth transactions
            amount = verusBridgeMaster.convertFromVerusNumber(uint256(_import.transfers[i].currencyvalue.amount),18);

            // if the transfer does not have the EXPORT_CURRENCY flag set
            if(_import.transfers[i].flags & CTRX_CURRENCY_EXPORT_FLAG != CTRX_CURRENCY_EXPORT_FLAG){

                if(_import.transfers[i].currencyvalue.currency == VerusConstants.VEth) {
                    // cast the destination as an ethAddress
                    assert(amount <= address(this).balance);
                    verusBridgeMaster.sendEth(amount,payable(verusBridgeMaster.bytesToAddress(_import.transfers[i].destination.destinationaddress)));
                    verusBridgeMaster.setEthHeld(verusBridgeMaster.getEthHeld() - amount);
            
                } else {
                    // handle erc20 transactions  
                    // amount conversion is handled in token manager
                    tokenManager.importERC20Tokens(_import.transfers[i].currencyvalue.currency,
                        _import.transfers[i].currencyvalue.amount,
                        verusBridgeMaster.bytesToAddress(_import.transfers[i].destination.destinationaddress));
                }
            } else {
                // If the type of address is a CCurrencyDefinition i.e. flag type DEST_REGISTERCURRENCY
                if(_import.transfers[i].destination.destinationtype & DEST_REGISTERCURRENCY == DEST_REGISTERCURRENCY)
                     tokenManager.deployNewToken(_import.transfers[i].destination.destinationaddress);
                
            }
            //handle the distributions of the fees
            //add them into the fees array to be claimed by the message sender
            if(_import.transfers[i].fees > 0 && _import.transfers[i].feecurrencyid == VerusConstants.VEth){
                verusBridgeMaster.setClaimableFees(msg.sender,_import.transfers[i].fees);
            }
        }
        return true;
    }
    
    function getReadyExportsByBlock(uint _blockNumber) public view returns(VerusObjects.CReserveTransferSet memory) {
        //need a transferset for each position not each block
        //retrieve a block get the indexes, create a transfer set for each index add those to the array
        uint eIndex = readyExportsByBlock[_blockNumber].index;

        VerusObjects.CReserveTransferSet memory output = VerusObjects.CReserveTransferSet(
            eIndex,                     // position in array
            _blockNumber,               // blockHeight
            readyExportHashes[eIndex],  // cross chain export hash
            _readyExports[eIndex]       // list of CReserveTransfers
        );

        return output;
    }

    function getReadyExportsByRange(uint _startBlock,uint _endBlock) public view returns(VerusObjects.CReserveTransferSet[] memory){
        //calculate the size that the return array will be to initialise it
        uint outputSize = 0;
        if(_startBlock < firstBlock) _startBlock = firstBlock;
        for(uint i = _startBlock; i <= _endBlock; i++){
            if(readyExportsByBlock[i].created) outputSize += 1;
        }

        VerusObjects.CReserveTransferSet[] memory output = new VerusObjects.CReserveTransferSet[](outputSize);
        uint outputPosition = 0;
        for (uint blockNumber = _startBlock; blockNumber <= _endBlock; blockNumber++){
            if (readyExportsByBlock[blockNumber].created) {
                output[outputPosition] = getReadyExportsByBlock(blockNumber);
                outputPosition++;
            }
        }
        return output;        
    }

}
