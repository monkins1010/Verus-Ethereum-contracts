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

contract VerusBridge {

    //list of erc20 tokens that can be accessed,
    //the contract must be able to mint and burn coins on the contract
    //defines the tokenManager which creates the erc20
    TokenManager tokenManager;
    VerusSerializer verusSerializer;
    VerusProof verusProof;
    VerusNotarizer verusNotarizer;
    VerusCrossChainExport verusCCE;

    //THE CONTRACT OWNER NEEDS TO BE REPLACED BY A SET OF NOTARIES
    address contractOwner;
    bool public deprecated = false; //indicates if the cotnract is deprecated
    address public upgradedAddress;
    uint256 public feesHeld = 0;
    uint256 public ethHeld = 0;
    uint256 public poolSize = 0;
    uint public firstBlock = 0;

    //used to prove the transfers the index of this corresponds to the index of the 
    bytes32[] public readyExportHashes;
    //DO NOT ADD ANY VARIABLES ABOVE THIS POINT
    //used to store a list of currencies and an amount
    VerusObjects.CReserveTransfer[] private _pendingExports;
    
    //stores the blockheight of each pending transfer
    //the export set holds the summary of a set of exports
    VerusObjects.CReserveTransfer[][] public _readyExports;
    
    //stores the index corresponds to the block
    VerusObjects.LastImport public lastimport;
    mapping(bytes32 => bool) public processedTxids;
    mapping (uint => VerusObjects.blockCreated) public readyExportsByBlock;
    mapping (address => uint256) public claimableFees;
    
    bytes[] public SerializedCRTs;
    bytes[] public SerializedCCEs;
    bytes32[] public hashedCRTs;
    uint public lastTxidimport;
    
    
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

    function isPoolAvailable(uint256 _feesAmount,address _feeCurrencyID) private view returns(bool){
        if(verusNotarizer.numNotarizedBlocks() >= 1) {
            //the bridge has been activated
            return false;
        } else {
            require(_feeCurrencyID == VerusConstants.VerusCurrencyId,"Bridge is not yet available only Verus can be used for fees");
            require(poolSize > _feesAmount,"Bridge is not yet available fees cannot exceed existing pool.");
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
        if(decimals > 8 ) {
            power = decimals - 8;// number of decimals in verus
            c = a / (10 ** power);
        }else if(decimals < 8){
            power = 8 - decimals;// number of decimals in verus
            c = a * (10 ** power);
        }
      
        return c;
    }
 
    function export(VerusObjects.CReserveTransfer memory transfer) public payable{
        require(!deprecated,"Contract has been deprecated");
        require(msg.value >= VerusConstants.transactionFee + uint64(transfer.fees),"Please send the appropriate transaction fee.");
        if(transfer.currencyvalue.currency != VerusConstants.VEth){
            //check there are enough fees sent
            feesHeld += msg.value;
            //check that the token is registered
            (address ERC20TokenAddress, bool VerusOwned, bool isRegistered) = tokenManager.verusToERC20mapping(transfer.currencyvalue.currency);
            require(isRegistered, "The token is not registered");
            Token token = Token(ERC20TokenAddress);
            uint256 allowedTokens = token.allowance(msg.sender,address(this));
            uint256 tokenAmount = convertFromVerusNumber(transfer.currencyvalue.amount,token.decimals()); //convert to wei from verus satoshis
            require( allowedTokens >= tokenAmount,"This contract must have an allowance of greater than or equal to the number of tokens");
            //transfer the tokens to this contract
            token.transferFrom(msg.sender,address(this),tokenAmount); 
            token.approve(address(tokenManager),tokenAmount);
            //give an approval for the tokenmanagerinstance to spend the tokens
            tokenManager.exportERC20Tokens(ERC20TokenAddress, tokenAmount);  //total amount kept as wei until export to verus
        } else {
            //handle a vEth transfer
            transfer.currencyvalue.amount = uint64(convertToVerusNumber(msg.value - VerusConstants.transactionFee,18));
            ethHeld += transfer.currencyvalue.amount;
            feesHeld += VerusConstants.transactionFee;
        }
        _createExports(transfer);
    }

    function _createExports(VerusObjects.CReserveTransfer memory newTransaction) private {
        uint currentHeight = block.number;
        uint exportIndex;
        bool newHash;

        //if there is fees in the pool spend those and not the amount that
        if(isPoolAvailable(newTransaction.fees,newTransaction.feecurrencyid)) {
            poolSize -= newTransaction.fees;
        }

        //check if the current block height has a set of transfers associated with it if so add to the existing array
        if(readyExportsByBlock[currentHeight].created) {
            //append to an existing array of transfers
            exportIndex = readyExportsByBlock[currentHeight].index;
            _readyExports[exportIndex].push(newTransaction);
            newHash = false;
        }
        else {
            _pendingExports.push(newTransaction);
            _readyExports.push(_pendingExports);
            exportIndex = _readyExports.length - 1;
            readyExportsByBlock[currentHeight] = VerusObjects.blockCreated(exportIndex,true);
            delete _pendingExports;
            newHash = true;
        }
       
        //create a cross chain export, serialize it and hash it
        
        VerusObjects.CCrossChainExport memory CCCE = verusCCE.generateCCE(_readyExports[exportIndex]);
        //create a hash of the CCCE
        
        bytes memory serializedCCE = verusSerializer.serializeCCrossChainExport(CCCE);
        bytes memory serializedTransfers = verusSerializer.serializeCReserveTransfers(_readyExports[exportIndex],false);
        SerializedCRTs.push(serializedTransfers);
        bytes32 hashedTransfers = keccak256(serializedTransfers);
        bytes memory toHash = abi.encodePacked(serializedCCE,serializedTransfers);
        SerializedCCEs.push(toHash);
        hashedCRTs.push(hashedTransfers);
        //bytes32 hashedTransfers = keccak256(serializedTransfers);
        //bytes memory toHash = abi.encodePacked(serializedCCE,serializedTransfers);
        bytes32 hashedCCE;
        bytes32 lastProofRoot = 0;
        if(exportIndex != 0)  lastProofRoot = readyExportHashes[exportIndex -1];
        hashedCCE = keccak256(abi.encodePacked(serializedCCE,lastProofRoot));
        
        //add the hashed value
        if(newHash) readyExportHashes.push(hashedCCE);
        else readyExportHashes[exportIndex] = hashedCCE;
        if(firstBlock == 0) firstBlock = currentHeight;
        
    }

    function getlastimportheight() public view returns(uint) {
        return lastTxidimport;
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

    function _createImports(VerusObjects.CReserveTransferImport memory _import) public returns(bool){

        if(processedTxids[_import.txid] == true) return false; 
        bytes32 txidfound;
        bytes memory sliced = _import.partialtransactionproof.components[0].elVchObj;
        assembly {
            txidfound := mload(add(sliced, 32))
        }
        require(_import.txid == txidfound, "Txid not correct in header"); //the txid should be present in the header
        bool proved = verusProof.proveImports(_import);
        require(proved,"Transfers do not prove against the last notarization");
        processedTxids[_import.txid] = true;
        if(lastTxidimport < _import.height)
            lastTxidimport = _import.height;
        uint256 amount;
        //check the transfers were in the hash.
        for(uint i = 0; i < _import.transfers.length; i++){
            //handle eth transactions
            amount = convertFromVerusNumber(uint256(_import.transfers[i].currencyvalue.amount),18);
            if(_import.transfers[i].currencyvalue.currency == VerusConstants.VEth) {
                //cast the destination as an ethAddress
                    require(amount <= address(this).balance,"Requested amount exceeds contract balance");
                    sendEth(amount,payable(address(_import.transfers[i].destination.destinationaddress)));
                    ethHeld -= amount;
        
           } else {
                //handle erc20 transactions  
                //amount convesrion is handled in token manager
                tokenManager.importERC20Tokens(_import.transfers[i].currencyvalue.currency,
                    _import.transfers[i].currencyvalue.amount,
                    _import.transfers[i].destination.destinationaddress);
           }
            //handle the distributions of the fees
            //add them into the fees array to be claimed by the message sender
            if(_import.transfers[i].fees > 0 && _import.transfers[i].feecurrencyid == VerusConstants.VEth){
                claimableFees[msg.sender] = claimableFees[msg.sender] + _import.transfers[i].fees;
            }
        }
        return true;
    }
    
    function getReadyExportsByBlock(uint _blockNumber) public view returns(VerusObjects.CReserveTransferSet memory){
        //need a transferset for each position not each block
        //retrieve a block get the indexes, create a transfer set for each index add those to the array
        uint eIndex = readyExportsByBlock[_blockNumber].index;
        VerusObjects.CReserveTransferSet memory output = VerusObjects.CReserveTransferSet(
            eIndex, //position in array
            _blockNumber, //blockHeight
            //readyExportHashes[eIndex],
            //DO WE NEED TO DO THIS
            readyExportHashes[eIndex],
            _readyExports[eIndex]
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
        for(uint blockNumber = _startBlock;blockNumber <= _endBlock;blockNumber++){
            if(readyExportsByBlock[blockNumber].created) {
                output[outputPosition] = getReadyExportsByBlock(blockNumber);
                outputPosition++;
            }
        }
        return output;        
    }
 
    function sendEth(uint256 _ethAmount,address payable _ethAddress) private {
        require(!deprecated,"Contract has been deprecated");
        //do we take fees here????
        
        _ethAddress.transfer(_ethAmount);
    }
   
    function claimFees() public returns(uint256){
        require(!deprecated,"Contract has been deprecated");
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
