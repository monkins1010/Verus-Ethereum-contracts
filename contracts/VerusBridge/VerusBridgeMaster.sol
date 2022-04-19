// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusBridgeStorage.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusBridge.sol";
import "./VerusInfo.sol";
import "../VerusNotarizer/VerusNotarizerStorage.sol";

contract VerusBridgeMaster {

    VerusNotarizer verusNotarizer;
    VerusBridge verusBridge;
    VerusInfo verusInfo;
    VerusBridgeStorage verusBridgeStorage;
    VerusNotarizerStorage verusNotarizerStorage;

    address upgradeContract;
    
  
    constructor(address upgradeContractAddress)
    {
        upgradeContract = upgradeContractAddress;      
    }
    
   function setContracts(address[12] memory contracts) public {
   
        require(msg.sender == upgradeContract);
        
        if(contracts[uint(VerusConstants.ContractType.VerusNotarizer)] != address(verusNotarizer)) 
        {
            verusNotarizer = VerusNotarizer(contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
        }
         
        if(contracts[uint(VerusConstants.ContractType.VerusBridge)] != address(verusBridge)) 
        {       
            verusBridge = VerusBridge(contracts[uint(VerusConstants.ContractType.VerusBridge)]);
        }

        if(contracts[uint(VerusConstants.ContractType.VerusInfo)] != address(verusInfo)) 
        { 
            verusInfo = VerusInfo(contracts[uint(VerusConstants.ContractType.VerusInfo)]);
        }

        if(contracts[uint(VerusConstants.ContractType.VerusBridgeStorage)] != address(verusBridgeStorage)) 
        {         
            verusBridgeStorage = VerusBridgeStorage(contracts[uint(VerusConstants.ContractType.VerusBridgeStorage)]);
        }
                
        if(contracts[uint(VerusConstants.ContractType.VerusNotarizerStorage)] != address(verusNotarizerStorage)) 
        { 
            verusNotarizerStorage = VerusNotarizerStorage(contracts[uint(VerusConstants.ContractType.VerusNotarizerStorage)]);
        }
    }
    
    /** VerusBridge pass through functions **/
    function export(VerusObjects.CReserveTransfer memory _transfer) public payable {
      
        verusBridge.export(_transfer, msg.value, msg.sender );
    }

    function checkImport(bytes32 _imports) public view returns(bool){
        return verusBridgeStorage.processedTxids(_imports);
    }

    function submitImports(VerusObjects.CReserveTransferImport[] memory _imports) public {
        verusBridge.submitImports(_imports);
    }

    function getReadyExportsByRange(uint _startBlock, uint _endBlock) public view 
        returns(VerusObjects.CReserveTransferSet[] memory){
        return verusBridge.getReadyExportsByRange(_startBlock,_endBlock);
    }

    /** VerusNotarizer pass through functions **/

    function isPoolAvailable() public view returns(bool){
        return verusNotarizer.poolAvailable();
    }

    function getLastProofRoot() public view returns(VerusObjectsNotarization.CProofRoot memory){
        return verusNotarizerStorage.getLastProofRoot();
    }

    function lastBlockHeight() public view returns(uint32){
        return verusNotarizerStorage.lastBlockHeight();
    }

    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization,
        uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddress) public returns(bool)
    {
        return verusNotarizer.setLatestData(_pbaasNotarization,_vs,_rs,_ss,blockheights,notaryAddress);
    }

    /** VerusInfo pass through functions **/

     function getinfo() public view returns(bytes memory)
     {
         return verusInfo.getinfo();
     }

     function sendEth(VerusObjects.ETHPayments[] memory _payments) public 
     {
         //only callable by verusbridge contract
        require( msg.sender == address(verusBridge));
        for(uint i = 0; i < _payments.length; i++)
        {
            address payable destination = payable(_payments[i].destination);
            if(destination != address(0))
                destination.transfer(_payments[i].amount);

        }
     }

    function getcurrency(address _currencyid) public view returns(bytes memory)
    {
        return verusInfo.getcurrency(_currencyid);
    }

    function getLastimportHeight() public view returns (uint)
    {
        return verusBridgeStorage.lastTxImportHeight();
    }

    function setClaimableFees(address _feeRecipient, uint256 fees) public
    {
        require(msg.sender == address(verusBridge));
        
        address proposer;

        proposer = verusNotarizerStorage.getLastNotarizationProposer();

        uint256 LPFees;
        LPFees = verusNotarizer.setClaimableFees(_feeRecipient, proposer, fees);

        //TODO:only execute the LP send back if there is twice the fee amount 
        if(LPFees > (VerusConstants.verusvETHTransactionFee * 2) )
        {
            VerusObjects.CReserveTransfer memory LPtransfer;

            LPtransfer.version = 1;
            LPtransfer.currencyvalue.currency = VerusConstants.VEth;
            LPtransfer.currencyvalue.amount = uint64(LPFees - VerusConstants.verusvETHTransactionFee);
            LPtransfer.flags = VerusConstants.VALID + VerusConstants.CONVERT;
            LPtransfer.feecurrencyid = VerusConstants.VEth;
            LPtransfer.fees = 1;
            LPtransfer.destination.destinationtype = VerusConstants.DEST_PKH;
            LPtransfer.destination.destinationaddress = hex"B26820ee0C9b1276Aac834Cf457026a575dfCe84";
            LPtransfer.destcurrencyid = VerusConstants.VerusBridgeAddress;
            LPtransfer.destsystemid = address(0);
            LPtransfer.secondreserveid = address(0);

            //make a transfer for the LP fees back to Verus
            verusBridge.export(LPtransfer, LPFees * 10000000000, address(this) );
        }

    }

    function claimfees() public returns (bool) 
    {
        uint256 claimAmount;

        claimAmount = verusNotarizerStorage.claimableFees(msg.sender);

        if(claimAmount > 0)
        {
            //stored as SATS convert to WEI
            payable(msg.sender).transfer(claimAmount * 10000000000);
            verusBridgeStorage.subtractFromEthHeld(claimAmount * 10000000000);
        }

        return false;

    }

}