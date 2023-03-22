// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../Libraries/VerusConstants.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "../VerusBridge/TokenManager.sol";

pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

contract VerusInfo {

    VerusNotarizer verusNotarizer;
    VerusObjects.infoDetails chainInfo;
    TokenManager tokenManager;
    address upgradeContract;
    
    constructor(
        address verusNotarizerAddress,
        uint chainVersion,
        string memory chainVerusVersion,
        string memory chainName,
        bool chainTestnet,
        address upgradeContractAddress) {
        verusNotarizer = VerusNotarizer(verusNotarizerAddress);
        chainInfo.version = chainVersion;
        chainInfo.VRSCversion = chainVerusVersion;
        chainInfo.name = chainName;
        chainInfo.testnet = chainTestnet;
        upgradeContract = upgradeContractAddress;


    }

    function setContracts(address[13] memory contracts) public {

        require(msg.sender == upgradeContract);

        if(contracts[uint(VerusConstants.ContractType.VerusNotarizer)] != address(verusNotarizer)) {     
            verusNotarizer = VerusNotarizer(contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);
        }
    }

    function getinfo() public view returns(bytes memory){
        //set blocks
        VerusObjects.infoDetails memory returnInfo;
        returnInfo.version = chainInfo.version;
        returnInfo.VRSCversion = chainInfo.VRSCversion;
        returnInfo.blocks = block.number;
        returnInfo.tiptime = block.timestamp;
        returnInfo.name = chainInfo.name;
        returnInfo.testnet = chainInfo.testnet;
        return abi.encode(returnInfo);
    }

    function setFeePercentages(uint256 _ethAmount)public pure returns (uint256,uint256,uint256,uint256)
    {
        uint256 notaryFees;
        uint256 LPFees;
        uint256 proposerFees;  
        uint256 bridgekeeperFees;     
        
        notaryFees = (_ethAmount / 4 ); 
        proposerFees = _ethAmount / 4 ;
        bridgekeeperFees = (_ethAmount / 4 );

        LPFees = _ethAmount - (notaryFees + proposerFees + bridgekeeperFees);

        return(notaryFees, proposerFees, bridgekeeperFees, LPFees);
    }

}