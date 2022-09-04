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
    mapping (address => uint256) public claimableFees;
     
    constructor(address upgradeContractAddress)
    {
        upgradeContract = upgradeContractAddress;      
    }
    
   function setContracts(address[12] memory contracts) public {
   
        require(msg.sender == upgradeContract);
        
        verusNotarizer = VerusNotarizer(contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
        verusBridge = VerusBridge(contracts[uint(VerusConstants.ContractType.VerusBridge)]);
        verusInfo = VerusInfo(contracts[uint(VerusConstants.ContractType.VerusInfo)]);
        verusBridgeStorage = VerusBridgeStorage(contracts[uint(VerusConstants.ContractType.VerusBridgeStorage)]);
        verusNotarizerStorage = VerusNotarizerStorage(contracts[uint(VerusConstants.ContractType.VerusNotarizerStorage)]);

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

    function getLastProofRoot() public view returns(bytes memory){

       return abi.encode(verusNotarizerStorage.getNotarization(verusNotarizerStorage.lastNotarizationTxid()).proofroots);

    }

    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization, bytes memory data) public returns(bool)
    {

        return verusNotarizer.setLatestData(_pbaasNotarization, data);
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

        proposer = verusNotarizerStorage.getLastNotarizationProposer(); //miner and staker 10%, 
        //exporter 10%

        uint256 LPFees;
        LPFees = verusNotarizer.setClaimableFees(_feeRecipient, proposer, fees);

        //NOTE:only execute the LP transfer if there is x10 the fee amount 
        if(LPFees > (VerusConstants.verusvETHTransactionFee * 10) && verusNotarizer.poolAvailable())
        {
            //VerusObjects.CReserveTransfer memory LPtransfer;
            //set burn flag
            //LPtransfer = verusInfo.lpTransfer(LPFees);

            //make a transfer for the LP fees back to Verus
            verusBridge.sendToVRSC(uint64(LPFees), true);
            //verusBridge.export(LPtransfer, LPFees * VerusConstants.SATS_TO_WEI_STD, address(this) );
        }
    }

    function claimfees() public returns (bool) 
    {
        uint256 claimAmount;
        claimAmount = claimableFees[msg.sender];

        if(claimAmount > 0)
        {
            //stored as SATS convert to WEI
            payable(msg.sender).transfer(claimAmount * VerusConstants.SATS_TO_WEI_STD);
            verusBridgeStorage.subtractFromEthHeld(claimAmount * VerusConstants.SATS_TO_WEI_STD);
        }

        return false;

    }
        
    function setClaimedFees(address _address, uint256 fees)public returns (uint256)
    {
        require(msg.sender == address(verusNotarizer));

        claimableFees[_address] += fees;

        return claimableFees[_address];
    }

    function sendVRSC() public 
    {
        require(msg.sender == address(verusNotarizer));
        verusBridge.sendToVRSC(0, false);
    }

}