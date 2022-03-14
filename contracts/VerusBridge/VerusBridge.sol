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
import "./ExportManager.sol";

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
    ExportManager exportManager;

    // THE CONTRACT OWNER NEEDS TO BE REPLACED BY A SET OF NOTARIES
    address contractOwner;

    bool public deprecated = false;     // indicates if the contract is deprecated
    address public upgradedAddress;     // new contract, if this is deprecated

    uint public firstBlock = 0;

    // used to prove the transfers the index of this corresponds to the index of the 
    bytes32[] public readyExportHashes;

    // DO NOT ADD ANY VARIABLES ABOVE THIS POINT
    // used to store a list of currencies and an amount
   // VerusObjects.CReserveTransfer[] private _pendingExports;
    
    // stores the blockheight of each pending transfer
    // the export set holds the summary of a set of exports
    mapping (uint => VerusObjects.exportSet) public _readyExports;
    
    //stores the index corresponds to the block
    VerusObjects.LastImport public lastimport;
    mapping (bytes32 => bool) public processedTxids;
    mapping (uint => VerusObjects.blockCreated) public readyExportsByBlock;
    
    uint public lastTxImportHeight;

    uint32 constant CTRX_CURRENCY_EXPORT_FLAG = 0x2000;
    uint8 constant DEST_REGISTERCURRENCY = 6;
    event Deprecate(address newAddress);
    
    constructor(address verusBridgeMasterAddress) {
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress); 
        lastimport.height = 0;
        lastimport.txid = 0x00000000000000000000000000000000;
    }

    function setContracts(address[] memory contracts) public {

        assert(msg.sender == address(verusBridgeMaster));

        if(contracts[uint(VerusConstants.ContractType.TokenManager)] != verusBridgeMaster.getContractAddress(VerusConstants.ContractType.TokenManager))
            tokenManager = TokenManager(contracts[uint(VerusConstants.ContractType.TokenManager)]);
        
        if(contracts[uint(VerusConstants.ContractType.VerusSerializer)] != verusBridgeMaster.getContractAddress(VerusConstants.ContractType.VerusSerializer))
            verusSerializer = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]);
        
        if(contracts[uint(VerusConstants.ContractType.VerusProof)] != verusBridgeMaster.getContractAddress(VerusConstants.ContractType.VerusProof))    
            verusProof = VerusProof(contracts[uint(VerusConstants.ContractType.VerusProof)]);

        if(contracts[uint(VerusConstants.ContractType.VerusNotarizer)] != verusBridgeMaster.getContractAddress(VerusConstants.ContractType.VerusNotarizer))     
            verusNotarizer = VerusNotarizer(contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);

        if(contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)] != verusBridgeMaster.getContractAddress(VerusConstants.ContractType.VerusCrossChainExport))     
            verusCCE = VerusCrossChainExport(contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)]);

        if(contracts[uint(VerusConstants.ContractType.ExportManager)] != verusBridgeMaster.getContractAddress(VerusConstants.ContractType.ExportManager))     
            exportManager = ExportManager(contracts[uint(VerusConstants.ContractType.ExportManager)]);

    }
 
    function export(VerusObjects.CReserveTransfer memory transfer, uint256 paidValue) public payable {

        uint256 fees;

        fees = exportManager.checkExport(transfer, msg.value);

        assert(fees != 0); 

        if (transfer.currencyvalue.currency != VerusConstants.VEth) {
            //check there are enough fees sent
            verusBridgeMaster.setFeesHeld(verusBridgeMaster.getFeesHeld() + paidValue);
            //check that the token is registered
            Token token = tokenManager.getTokenERC20(transfer.currencyvalue.currency);
            uint256 allowedTokens = token.allowance(msg.sender,address(this));
            uint256 tokenAmount = verusCCE.convertFromVerusNumber(transfer.currencyvalue.amount,token.decimals()); //convert to wei from verus satoshis
            assert( allowedTokens >= tokenAmount);
            //transfer the tokens to this contract
            token.transferFrom(msg.sender,address(this),tokenAmount); 
            token.approve(address(tokenManager),tokenAmount);
            //give an approval for the tokenmanagerinstance to spend the tokens
            tokenManager.exportERC20Tokens(transfer.currencyvalue.currency, tokenAmount);  //total amount kept as wei until export to verus
        } else {
            //handle a vEth transfer
            transfer.currencyvalue.amount = uint64(verusCCE.convertToVerusNumber(msg.value - VerusConstants.transactionFee,18));
            verusBridgeMaster.addToEthHeld(msg.value - fees);  // msg.value == fees +amount in transaction checked in checkExport()
            verusBridgeMaster.addToFeesHeld(fees); //TODO: what happens if they send to much fee?
        }
        _createExports(transfer);
    }

    function _createExports(VerusObjects.CReserveTransfer memory newTransaction) private {
        uint currentHeight = block.number;

        //check if the current block height has a set of transfers associated with it if so add to the existing array

        _readyExports[currentHeight].transfers.push(newTransaction);

        bool bridgeReady = verusBridgeMaster.poolAvailable(VerusConstants.VerusBridgeAddress);

        bytes memory serializedCCE = verusSerializer.serializeCCrossChainExport(verusCCE.generateCCE(_readyExports[currentHeight].transfers, bridgeReady));

        _readyExports[currentHeight].txidhash = keccak256(abi.encodePacked(serializedCCE, _readyExports[currentHeight].txidhash));

        if (firstBlock == 0) { 
            firstBlock = currentHeight;
        }
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
            amount = verusCCE.convertFromVerusNumber(uint256(_import.transfers[i].currencyvalue.amount),18);

            // if the transfer does not have the EXPORT_CURRENCY flag set
            if(_import.transfers[i].flags & VerusConstants.CTRX_CURRENCY_EXPORT_FLAG != VerusConstants.CTRX_CURRENCY_EXPORT_FLAG){
                    address destinationAddress;

                    bytes memory tempAddress  = _import.transfers[i].destination.destinationaddress;

                    assembly {
                    destinationAddress := mload(add(tempAddress, 20))
                    } 

                if(destinationAddress != address(0)){
                    if(_import.transfers[i].currencyvalue.currency == VerusConstants.VEth) {
                        // cast the destination as an ethAddress
                        assert(amount <= address(this).balance);
                            verusBridgeMaster.sendEth(amount, payable(destinationAddress));
                            verusBridgeMaster.subtractFromEthHeld(amount);
                            
                
                    } else {
                        // handle erc20 transactions  
                        // amount conversion is handled in token manager

                        tokenManager.importERC20Tokens(_import.transfers[i].currencyvalue.currency,
                            _import.transfers[i].currencyvalue.amount,
                            destinationAddress);
                    }
                }
            } else if(_import.transfers[i].destination.destinationtype & VerusConstants.DEST_REGISTERCURRENCY == VerusConstants.DEST_REGISTERCURRENCY) {
                     
                tokenManager.deployToken(_import.transfers[i].destination.destinationaddress);
                
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
        VerusObjects.CReserveTransferSet memory output = VerusObjects.CReserveTransferSet(
            _blockNumber,                     // position in array
            _blockNumber,               // blockHeight
            _readyExports[_blockNumber].txidhash,  // cross chain export hash
            _readyExports[_blockNumber].transfers       // list of CReserveTransfers
        );
        return output;
    }

    function getReadyExportsByRange(uint _startBlock,uint _endBlock) public view returns(VerusObjects.CReserveTransferSet[] memory returnedExports){
        //calculate the size that the return array will be to initialise it
        uint outputSize = 0;
        if(_startBlock < firstBlock) _startBlock = firstBlock;
        for(uint i = _startBlock; i <= _endBlock; i++){
            if(readyExportsByBlock[i].created) outputSize += 1;
        }

        uint outputPosition = 0;
        for (uint blockNumber = _startBlock; blockNumber <= _endBlock; blockNumber++){
            if (readyExportsByBlock[blockNumber].created) {
                returnedExports[outputPosition] = getReadyExportsByBlock(blockNumber);
                outputPosition++;
            }
        }
        return returnedExports;        
    }

    function getCreatedExport(uint created) public view returns (address) {

        if (_readyExports[created].transfers.length > 0)
            return  _readyExports[created].transfers[0].destcurrencyid;
        else
            return address(0);
        
    }

}
