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
    uint32 constant CONFIRMED_PROPOSER = 128;
    uint32 constant LATEST_PROPOSER = 256;
     
    constructor(address upgradeContractAddress)
    {
        upgradeContract = upgradeContractAddress;      
    }

    receive() external payable {
        
    }
    
   function setContracts(address[13] memory contracts) public {
   
        require(msg.sender == upgradeContract);
        
        verusNotarizer = VerusNotarizer(contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
        verusBridge = VerusBridge(contracts[uint(VerusConstants.ContractType.VerusBridge)]);
        verusInfo = VerusInfo(contracts[uint(VerusConstants.ContractType.VerusInfo)]);
        verusBridgeStorage = VerusBridgeStorage(contracts[uint(VerusConstants.ContractType.VerusBridgeStorage)]);
        verusNotarizerStorage = VerusNotarizerStorage(contracts[uint(VerusConstants.ContractType.VerusNotarizerStorage)]);

    }

    function transferETH (address newMasterAddress) public {
        require(msg.sender == upgradeContract);
        payable(newMasterAddress).send(address(this).balance);
    }
    
    /** VerusBridge pass through functions **/
    function export(VerusObjects.CReserveTransfer memory _transfer) public payable {
      
        verusBridge.export(_transfer, msg.value, msg.sender );
    }

    function checkImport(bytes32 _imports) public view returns(bool){
        return verusBridgeStorage.processedTxids(_imports);
    }

    function submitImports(VerusObjects.CReserveTransferImport calldata _imports) external {

        uint176 bridgeKeeper;

        bridgeKeeper = uint176(uint160(msg.sender));

        bridgeKeeper |= (uint176(0x0c14) << 160); //make ETH type '0c' and length 20 '14'

        uint64 fees = verusBridge._createImports(_imports);
        if (fees >  0)
        {
            setClaimableFees(fees, bridgeKeeper);
        }
    }

    function getReadyExportsByRange(uint _startBlock, uint _endBlock) public view 
            returns(VerusObjects.CReserveTransferSet[] memory){

        return verusBridge.getReadyExportsByRange(_startBlock,_endBlock);
    }

    /** VerusNotarizer pass through functions **/

    function isPoolAvailable() public view returns(bool){
        return verusNotarizer.poolAvailable();
    }

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
                destination.send(_payments[i].amount);
                totalsent += _payments[i].amount;
            }
        }
    }

    function getcurrency(address _currencyid) public view returns(bytes memory)
    {
        return verusInfo.getcurrency(_currencyid);
    }

    function setClaimableFees(uint64 fees, uint176 bridgekeeper) private
    {
        uint256 notaryFees;
        uint256 LPFee;
        uint256 proposerFees;  
        uint256 bridgekeeperFees;              
        uint176 proposer;
        bytes memory proposerBytes = verusNotarizer.bestForks(0);

        assembly {
                proposer := mload(add(proposerBytes, 128))
        } 

        (notaryFees, proposerFees, bridgekeeperFees, LPFee) = verusInfo.setFeePercentages(fees);

        // Any remainder from Notaries shared fees is put into the LPFees pot.
        LPFee += setNotaryFees(notaryFees);

        setClaimedFees(bytes32(uint256(proposer)), proposerFees);
        setClaimedFees(bytes32(uint256(bridgekeeper)), bridgekeeperFees);

        //NOTE: LP fees to be sent to vrsc to be burnt held at the verusNotarizerStorage address as a unique key
        uint256 totalLPFees = setClaimedFees(bytes32(uint256(uint160(address(verusNotarizerStorage)))), LPFee);
        
        //NOTE:only execute the LP transfer if there is x10 the fee amount 
        if(totalLPFees > (VerusConstants.verusvETHTransactionFee * 10) && verusNotarizer.poolAvailable())
        {
            //make a transfer for the LP fees back to Verus
            verusBridge.sendToVRSC(uint64(totalLPFees), true, address(0));
            verusNotarizerStorage.setClaimableFees(bytes32(uint256(uint160(address(verusNotarizerStorage)))), 0);
        }
    }

    function setNotaryFees(uint256 notaryFees) private returns (uint64 remainder){  //sent in as SATS
      
        uint256 numOfNotaries = verusNotarizer.currentNotariesLength();
        uint64 notariesShare = uint64(notaryFees / numOfNotaries);
        for (uint i=0; i < numOfNotaries; i++)
        {
            uint176 notary;
            notary = uint176(uint160(verusNotarizer.getNotaryETHAddress(i)));
            notary |= (uint176(0x0c14) << 160); //set at type eth
            setClaimedFees(bytes32(uint256(notary)), notariesShare);
        }
        remainder = uint64(notaryFees % numOfNotaries);
    }

    function claimfees() public
    {
        uint256 claimAmount;
        uint256 claiment;

        claiment = uint256(uint160(msg.sender));

        // Check claiment is type eth with length 20 and has fees to be got.
        claiment |= (uint256(0x0c14) << 160);
        claimAmount = verusNotarizerStorage.claimableFees(bytes32(claiment));

        if(claimAmount > 0)
        {
            //stored as SATS convert to WEI
            payable(msg.sender).transfer(claimAmount * VerusConstants.SATS_TO_WEI_STD);
            verusNotarizerStorage.setClaimableFees(bytes32(claiment),  0);
        }
        else
        {
            revert("No fees avaiable");
        }
    }

    function getNewProof(bool latest) public payable returns (bytes memory) {

        uint256 feeCost;

        feeCost = verusNotarizer.getProofCosts(latest);

        require(msg.value == feeCost, "Not enough fee");

        uint256 feeShare = msg.value / VerusConstants.SATS_TO_WEI_STD / 2;
        uint256 remainder = (msg.value / VerusConstants.SATS_TO_WEI_STD) % 2;

        uint256 proposerAndHeight;
        bytes memory proposerBytes = verusNotarizer.bestForks(0);

        uint32 proposeroffset = latest ? LATEST_PROPOSER : CONFIRMED_PROPOSER;

        assembly {
                proposerAndHeight := mload(add(proposerBytes, proposeroffset))
        } 
        
        // Proposer and notaries get share of fees
        // any remainder from divide by 2 or divide by notaries gets added
        feeShare += setNotaryFees(feeShare);
        setClaimedFees(bytes32(uint256(uint176(proposerAndHeight))), (feeShare + remainder));

        return verusNotarizer.getNewProofs(bytes32(proposerAndHeight));
    }

    function getProofByHeight(uint height) public payable returns (bytes memory) {

        return verusNotarizer.getProof(height);
    }

    function getProofCost(bool latest) public view returns (uint256) {

        return verusNotarizer.getProofCosts(latest);
    }

    function sendfees(bytes32 publicKeyX, bytes32 publicKeyY) public 
    {
        uint8 leadingByte;

        leadingByte = (uint256(publicKeyY) & 1) == 1 ? 0x03 : 0x02;

        address rAddress = address(ripemd160(abi.encodePacked(sha256(abi.encodePacked(leadingByte, publicKeyX)))));
        address ethAddress = address(uint160(uint256(keccak256(abi.encodePacked(publicKeyX, publicKeyY)))));

        uint256 claiment; 

        claiment = uint256(uint160(rAddress));

        claiment |= (uint256(0x0214) << 160);  // is Claimient type R address and 20 bytes.

        if ((verusNotarizerStorage.claimableFees(bytes32(claiment)) > VerusConstants.verusvETHTransactionFee) && msg.sender == ethAddress)
        {
            verusBridge.sendToVRSC(uint64(verusNotarizerStorage.claimableFees(bytes32(claiment))), true, rAddress); //sent in as SATS
            verusNotarizerStorage.setClaimableFees(bytes32(claiment),  0);
        }
        else
        {
            revert("No fees avaiable");
        }

    }
        
    function setClaimedFees(bytes32 _address, uint256 fees) private returns (uint256)
    {
        return verusNotarizerStorage.appendClaimableFees(_address, fees);
    }

    function sendVRSC() public 
    {
        require(msg.sender == address(verusNotarizer));
        verusBridge.sendToVRSC(0, false, address(0));
    }

}