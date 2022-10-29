// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";
import "../VerusBridge/VerusBridgeStorage.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusBridge.sol";
import "./VerusInfo.sol";
import "../VerusNotarizer/VerusNotarizerStorage.sol";

import "./UpgradeManager.sol";

contract VerusBridgeMaster {

    VerusNotarizer verusNotarizer;
    VerusBridge verusBridge;
    VerusInfo verusInfo;
    VerusBridgeStorage verusBridgeStorage;
    VerusNotarizerStorage verusNotarizerStorage;

    address upgradeContract;
    mapping (bytes32 => uint256) public claimableFees;
    uint256 ethHeld = 0;
     
    constructor(address upgradeContractAddress)
    {
        upgradeContract = upgradeContractAddress;      
    }
    
   function setContracts(address[13] memory contracts) public {
   
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

    function submitImports(VerusObjects.CReserveTransferImport calldata _imports) public {

        uint176 bridgeKeeper;

        bridgeKeeper = uint176(uint160(msg.sender));

        bridgeKeeper |= (uint176(0x0c14) << 160); //make ETH type and length 20

        verusBridge._createImports(_imports, bridgeKeeper);
    }

    function getReadyExportsByRange(uint _startBlock, uint _endBlock) public view 
        returns(VerusObjects.CReserveTransferSet[] memory){
        return verusBridge.getReadyExportsByRange(_startBlock,_endBlock);
    }

    /** VerusNotarizer pass through functions **/

    function isPoolAvailable() public view returns(bool){
        return verusNotarizer.poolAvailable();
    }

    function setLatestData(bytes calldata serializedNotarization, bytes32 txid, uint32 n, bytes memory data) public 
    {

        require(verusNotarizer.setLatestData(serializedNotarization, txid, n, data), "not enough notary signatures");

        verusNotarizer.checkNotarization(serializedNotarization, txid, n);

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
        uint256 totalsent;
        for(uint i = 0; i < _payments.length; i++)
        {
            address payable destination = payable(_payments[i].destination);
            if(destination != address(0))
            {
                destination.transfer(_payments[i].amount);
                totalsent += _payments[i].amount;
            }

        }
        subtractFromEthHeld(totalsent);
    }

    function getcurrency(address _currencyid) public view returns(bytes memory)
    {
        return verusInfo.getcurrency(_currencyid);
    }

    function setClaimableFees(bytes32 _feeRecipient, uint256 fees, uint176 bridgekeeper) public
    {
        require(msg.sender == address(verusBridge));
        
        //exporter 10%

        uint256 LPFees;
        LPFees = setLPClaimableFees(_feeRecipient, fees, bridgekeeper);

        //NOTE:only execute the LP transfer if there is x10 the fee amount 
        if(LPFees > (VerusConstants.verusvETHTransactionFee * 10) && verusNotarizer.poolAvailable())
        {
        
            //make a transfer for the LP fees back to Verus
            verusBridge.sendToVRSC(uint64(LPFees), true, address(0));
            //verusBridge.export(LPtransfer, LPFees * VerusConstants.SATS_TO_WEI_STD, address(this) );
        }
    }

    function setLPClaimableFees(bytes32 _feeRecipient, uint256 _ethAmount, uint176 bridgekeeper) private returns (uint256){

       
        uint256 notaryFees;
        uint256 LPFees;
        uint256 exporterFees;
        uint256 proposerFees;  
        uint256 bridgekeeperFees;              

        uint176 proposer;
        uint8 proposerType;
        bytes memory proposerBytes = verusNotarizer.bestForks(0);

        assembly {
                proposer := mload(add(proposerBytes, 128))
        } 

        (notaryFees, exporterFees, proposerFees, bridgekeeperFees, LPFees) = verusInfo.setFeePercentages(_ethAmount);

        setNotaryFees(notaryFees);
        setClaimedFees(_feeRecipient, exporterFees);

        if (proposerType == VerusConstants.DEST_ETH)
        {
            setClaimedFees(bytes32(uint256(proposer)), proposerFees);
        }

        setClaimedFees(bytes32(uint256(bridgekeeper)), bridgekeeperFees);

        //return total amount of unclaimed LP Fees accrued.  Verusnotarizer address is the key.
        return setClaimedFees(bytes32(uint256(uint160(address(verusNotarizer)))), LPFees);
              
    }


    function setNotaryFees(uint256 notaryFees) public {
        
        uint32 psudorandom = uint32(uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp))));

        uint32 notaryTurn = uint32(psudorandom % (verusNotarizer.currentNotariesLength()));

        uint176 notary;

        notary = uint176(uint160(verusNotarizer.getNotaryETHAddress(notaryTurn)));

        notary |= (uint176(0x0c14) << 160); 

        setClaimedFees(bytes32(uint256(notary)), notaryFees);
    }

    function claimfees() public returns (bool) 
    {
        uint256 claimAmount;
        uint256 claiment;

        claiment = uint256(uint160(msg.sender));

        // Check claiment is type eth with length 20
        claiment |= (uint256(0x0c14) << 160);
        claimAmount = claimableFees[bytes32(claiment)];

        if(claimAmount > 0)
        {
            //stored as SATS convert to WEI
            payable(msg.sender).transfer(claimAmount * VerusConstants.SATS_TO_WEI_STD);
            subtractFromEthHeld(claimAmount * VerusConstants.SATS_TO_WEI_STD);
        }

        return false;

    }

    function sendfees(bytes memory pubKey) public 
    {
        address rAddress = address(ripemd160(abi.encodePacked(sha256(abi.encodePacked(sha256(pubKey))))));
        address ethAddress = address(uint160(uint256(keccak256(pubKey))));

        uint256 claiment; 

        claiment = uint256(uint160(rAddress));

        claiment |= (uint256(0x0214) << 160);  // is Claimient type R address and 20 bytes.

        if ((claimableFees[bytes32(claiment)] > 0) && msg.sender == ethAddress)
        {
            verusBridge.sendToVRSC(uint64(claimableFees[bytes32(claiment)]), true, rAddress);
        }
        else
        {
            revert("No fees avaiable");
        }

    }
        
    function setClaimedFees(bytes32 _address, uint256 fees) private returns (uint256)
    {
        claimableFees[_address] += fees;

        return claimableFees[_address];
    }

    function sendVRSC() public 
    {
        require(msg.sender == address(verusNotarizer));
        verusBridge.sendToVRSC(0, false, address(0));
    }

    function addToEthHeld(uint256 _ethAmount) public {
        require( msg.sender == address(verusBridge));
        ethHeld += _ethAmount;
    }

    function subtractFromEthHeld(uint256 _ethAmount) private {

        ethHeld -= _ethAmount;
    }
}