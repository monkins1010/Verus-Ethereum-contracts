// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../Libraries/VerusConstants.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "../VerusBridge/VerusBridgeMaster.sol";
import "../VerusBridge/TokenManager.sol";

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

contract VerusInfo {

    VerusNotarizer verusNotarizer;
    VerusObjects.infoDetails chainInfo;
    TokenManager tokenManager;
    address upgradeContract;
    address contractOwner;
    
    constructor(
        address verusNotarizerAddress,
        uint chainVersion,
        string memory chainVerusVersion,
        string memory chainName,
        bool chainTestnet,
        address upgradeContractAddress,
        address tokenManagerAddress) {
        verusNotarizer = VerusNotarizer(verusNotarizerAddress);
        chainInfo.version = chainVersion;
        chainInfo.VRSCversion = chainVerusVersion;
        chainInfo.name = chainName;
        chainInfo.testnet = chainTestnet;
        upgradeContract = upgradeContractAddress;
        tokenManager = TokenManager(tokenManagerAddress);
        contractOwner = msg.sender;
    }

    function setContracts(address[12] memory contracts) public {

        require(msg.sender == upgradeContract);

        if(contracts[uint(VerusConstants.ContractType.TokenManager)] != address(tokenManager)) {
            tokenManager = TokenManager(contracts[uint(VerusConstants.ContractType.TokenManager)]);
        }
  
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

    function getcurrency(address _currencyid) public view returns(bytes memory){
        VerusObjects.currencyDetail memory returnCurrency;
        returnCurrency.version = chainInfo.version;
        //if the _currencyid is null then return VEth
        address[] memory notaries = verusNotarizer.getNotaries();
        uint8 minnotaries = verusNotarizer.currentNotariesRequired();
        
        address currencyAddress;
        uint256 initialsupply;
        if(_currencyid == VerusConstants.VEth){
            currencyAddress = VerusConstants.VEth;
            initialsupply = 72000000;
        } else {
            currencyAddress = _currencyid;
            initialsupply = 0;
        }
            
            
        returnCurrency = VerusObjects.currencyDetail(
                chainInfo.version,
                VerusConstants.currencyName,
                VerusConstants.VEth,
                VerusConstants.VerusSystemId,
                VerusConstants.VerusSystemId,
                2,
                3,
                VerusObjectsCommon.CTransferDestination(9,abi.encodePacked(currencyAddress)),
                VerusConstants.VerusSystemId,
                0,
                0,
                initialsupply,
                initialsupply,
                VerusConstants.VEth,
                notaries,
                minnotaries
        );

        return abi.encode(returnCurrency);
    }

    function launchTokens(VerusObjects.setupToken[] memory tokensToDeploy) public  {

        require(msg.sender == contractOwner,"INFO:contractOwnerRequired");

        tokenManager.launchTokens(tokensToDeploy);

        //blow the fuse
        contractOwner = address(0);
    }
}