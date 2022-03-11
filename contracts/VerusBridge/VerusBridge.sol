// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../Libraries/VerusConstants.sol";
import "./TokenManager.sol";
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
    ExportManager exportManager;

    // THE CONTRACT OWNER NEEDS TO BE REPLACED BY A SET OF NOTARIES
    address contractOwner;

    bool public deprecated = false;     // indicates if the contract is deprecated
    address public upgradedAddress;     // new contract, if this is deprecated

    uint256 public feesHeld = 0;
    uint256 public ethHeld = 0;
    uint256 public poolSize = 0;

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
    mapping (address => uint256) public claimableFees;

    uint public lastTxImportHeight;

    event Deprecate(address newAddress);
    
    constructor(address verusProofAddress,
        address tokenManagerAddress,
        address verusSerializerAddress,
        address verusNotarizerAddress,
        address verusCCEAddress,
        uint256 _poolSize) public {
        contractOwner = msg.sender; 
        verusProof =  VerusProof(verusProofAddress);
        tokenManager = TokenManager(tokenManagerAddress);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        verusNotarizer = VerusNotarizer(verusNotarizerAddress);
        verusCCE = VerusCrossChainExport(verusCCEAddress);
        poolSize = _poolSize;
        lastimport.height = 0;
        lastimport.txid = 0x00000000000000000000000000000000;
    }

    function isPoolUnavailable(uint256 _feesAmount,address _feeCurrencyID) public view returns(bool){

        if(0 < verusNotarizer.poolAvailable(VerusConstants.VerusBridgeAddress) &&
            verusNotarizer.poolAvailable(VerusConstants.VerusBridgeAddress) < uint32(block.number)) {
            //the bridge has been activated
            return false;
        } else {
            assert(_feeCurrencyID == VerusConstants.VerusCurrencyId);
            assert(poolSize >= _feesAmount);
            return true;
        }
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

    function convertToVerusNumber(uint256 a,uint8 decimals) public pure returns (uint256) {
         uint8 power = 10; //default value for 18
         uint256 c = a;
        if (decimals > 8 ) {
            power = decimals - 8;// number of decimals in verus
            c = a / (10 ** power);
        } else if (decimals < 8){
            power = 8 - decimals;// number of decimals in verus
            c = a * (10 ** power);
        }

        return c;
    }

    function setExportManagerContract(address newAddress) public payable returns (address) {

        assert(contractOwner == msg.sender);
                exportManager = ExportManager(newAddress);
        
        return newAddress;

    }

    function getCreatedExport(uint created) public view returns (address) {

        return  _readyExports[created][0].destcurrencyid;
        
    }
 
    function export(VerusObjects.CReserveTransfer memory transfer) public payable {

        uint256 fees;

        fees = exportManager.checkExport(transfer, msg.value);

        assert(fees != 0); 

        if (transfer.currencyvalue.currency != VerusConstants.VEth) {
            //check there are enough fees sent
            feesHeld += msg.value;
            //check that the token is registered
            Token token = tokenManager.getTokenERC20(transfer.currencyvalue.currency);
            uint256 allowedTokens = token.allowance(msg.sender,address(this));
            uint256 tokenAmount = convertFromVerusNumber(transfer.currencyvalue.amount,token.decimals()); //convert to wei from verus satoshis
            require( allowedTokens >= tokenAmount, "Not enough allowed tokens");
            //transfer the tokens to this contract
            token.transferFrom(msg.sender,address(this),tokenAmount); 
            token.approve(address(tokenManager),tokenAmount);
            //give an approval for the tokenmanagerinstance to spend the tokens
            tokenManager.exportERC20Tokens(transfer.currencyvalue.currency, tokenAmount);  //total amount kept as wei until export to verus
        } else {
            //handle a vEth transfer
            transfer.currencyvalue.amount = uint64(convertToVerusNumber(msg.value - VerusConstants.transactionFee,18));
            ethHeld += (msg.value - fees);  // msg.value == fees +amount in transaction checked in checkExport()
            feesHeld += fees; //TODO: what happens if they send to much fee?
        }
        _createExports(transfer);
    }

    function _createExports(VerusObjects.CReserveTransfer memory newTransaction) private {
        uint currentHeight = block.number;
        uint exportIndex;
        bool newHash;

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

    function bytesToAddress(bytes memory bys) private pure returns (address addr) {
    assembly {
      addr := mload(add(bys,20))
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
            amount = convertFromVerusNumber(uint256(_import.transfers[i].currencyvalue.amount),18);

            // if the transfer does not have the EXPORT_CURRENCY flag set
            if(_import.transfers[i].flags & VerusConstants.CTRX_CURRENCY_EXPORT_FLAG != VerusConstants.CTRX_CURRENCY_EXPORT_FLAG){

                if(bytesToAddress(_import.transfers[i].destination.destinationaddress) != address(0)){

                    if(_import.transfers[i].currencyvalue.currency == VerusConstants.VEth) {
                        // cast the destination as an ethAddress
                        assert(amount <= address(this).balance);
                            sendEth(amount,payable(bytesToAddress(_import.transfers[i].destination.destinationaddress)));
                            ethHeld -= amount;
                            
                
                    } else {
                        // handle erc20 transactions  
                        // amount conversion is handled in token manager

                        tokenManager.importERC20Tokens(_import.transfers[i].currencyvalue.currency,
                            _import.transfers[i].currencyvalue.amount,
                            bytesToAddress(_import.transfers[i].destination.destinationaddress));
                    }
                }
            } else if(_import.transfers[i].destination.destinationtype & VerusConstants.DEST_REGISTERCURRENCY == VerusConstants.DEST_REGISTERCURRENCY) {
                     
                tokenManager.deployToken(_import.transfers[i].destination.destinationaddress);
                
            }
            //handle the distributions of the fees
            //add them into the fees array to be claimed by the message sender
            if(_import.transfers[i].fees > 0 && _import.transfers[i].feecurrencyid == VerusConstants.VEth){
                claimableFees[msg.sender] = claimableFees[msg.sender] + _import.transfers[i].fees;
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
 
    function sendEth(uint256 _ethAmount, address payable _ethAddress) private {
        assert(!deprecated);
        //do we take fees here????
        
        _ethAddress.transfer(_ethAmount);
    }
   
    function claimFees() public returns(uint256) {
        assert(!deprecated);
        if(claimableFees[msg.sender] > 0 ){
            sendEth(claimableFees[msg.sender],msg.sender);
        }
        return claimableFees[msg.sender];
    }
/*
    function deprecate(address _upgradedAddress,bytes32 _addressHash,uint8[] memory _vs,bytes32[] memory _rs,bytes32[] memory _ss) public{
        if(verusNotarizer.notarizedDeprecation(_upgradedAddress, _addressHash, _vs, _rs, _ss)){
            deprecated = true;
            upgradedAddress = _upgradedAddress;
            Deprecate(_upgradedAddress);
        }
    }
*/

}
