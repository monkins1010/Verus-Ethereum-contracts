// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 < 0.9.0;
pragma experimental ABIEncoderV2;

library VerusConstants {
    
    address constant public VEth = 0x67460C2f56774eD27EeB8685f29f6CEC0B090B00;
    address constant public EthSystemID = VEth;
    address constant public VerusSystemId = 0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d;
    address constant public VerusCurrencyId = 0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d;
    //does this need to be set 
    address constant public RewardAddress = 0xB26820ee0C9b1276Aac834Cf457026a575dfCe84;
    uint8 constant public RewardAddressType = 4;
    uint256 constant public transactionFee = 100000000000000; //0.0001 eth
    string constant public currencyName = "VETH";
}