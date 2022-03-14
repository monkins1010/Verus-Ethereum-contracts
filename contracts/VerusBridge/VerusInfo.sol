// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsCommon.sol";
import "../Libraries/VerusConstants.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "../VerusBridge/VerusBridgeMaster.sol";

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

contract VerusInfo {

    VerusNotarizer verusNotarizer;
    VerusBridgeMaster verusBridgeMaster;
    VerusObjects.infoDetails chainInfo;
    
    constructor(
        address verusNotarizerAddress,
        uint chainVersion,
        string memory chainVerusVersion,
        string memory chainName,
        bool chainTestnet,
        address verusBridgeMasterAddress) public {
        verusNotarizer = VerusNotarizer(verusNotarizerAddress);
        chainInfo.version = chainVersion;
        chainInfo.VRSCversion = chainVerusVersion;
        chainInfo.name = chainName;
        chainInfo.testnet = chainTestnet;
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress);
    }

    function updateNotarizerAddress() public returns (address) {

    if (address(verusNotarizer) != verusBridgeMaster.getContractAddress(VerusConstants.ContractType.VerusNotarizer)) {
            verusNotarizer = VerusNotarizer(verusBridgeMaster.getContractAddress(VerusConstants.ContractType.VerusNotarizer));
            return address(verusNotarizer);
        }
        return address(0);
    }

    function getinfo() public view returns(VerusObjects.infoDetails memory){
        //set blocks
        VerusObjects.infoDetails memory returnInfo;
        returnInfo.version = chainInfo.version;
        returnInfo.VRSCversion = chainInfo.VRSCversion;
        returnInfo.blocks = block.number;
        returnInfo.tiptime = block.timestamp;
        returnInfo.name = chainInfo.name;
        returnInfo.testnet = chainInfo.testnet;
        return returnInfo;
    }

    function getcurrency(address _currencyid) public view returns(VerusObjects.currencyDetail memory){
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

        return returnCurrency;
    }
}