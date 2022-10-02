// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 < 0.9.0;
pragma abicoder v2;

library VerusConstants {
    address constant public VEth = 0x67460C2f56774eD27EeB8685f29f6CEC0B090B00;
    address constant public EthSystemID = VEth;
    address constant public VerusSystemId = 0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d;
    address constant public VerusCurrencyId = 0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d;
    address constant public VerusUSDCId = 0xF0A1263056c30E221F0F851C36b767ffF2544f7F;
    address constant public VerusBridgeAddress = 0xffEce948b8A38bBcC813411D2597f7f8485a0689;
    uint256 constant public transactionFee = 3000000000000000; //0.003 ETH 18 decimals
    string constant public currencyName = "VETH";
    uint64 constant public verusTransactionFee = 2000000; //0.02 VRSC
    uint64 constant public verusvETHTransactionFee = 300000; //0.003 vETH 10 decimasls
    uint32 constant  VALID = 1;
    uint32 constant  CONVERT = 2;
    uint32 constant  CROSS_SYSTEM = 0x40; 
    uint32 constant  BURN_CHANGE_PRICE = 0x80;              
    uint32 constant  IMPORT_TO_SOURCE = 0x200;          
    uint32 constant  RESERVE_TO_RESERVE = 0x400; 
    uint32 constant  CURRENCY_EXPORT = 0x2000;

    uint32 constant INVALID_FLAGS = 0xffffffff - (VALID + CONVERT + RESERVE_TO_RESERVE + IMPORT_TO_SOURCE + CURRENCY_EXPORT);

    uint8 constant DEST_PKH = 2;
    uint8 constant DEST_SH = 3;
    uint8 constant DEST_ID = 4;
    uint8 constant DEST_REGISTERCURRENCY = 6;
    uint8 constant DEST_ETH = 9;
    uint8 constant DEST_ETHNFT = 10;
    uint8 constant FLAG_DEST_AUX = 64;
    uint8 constant FLAG_DEST_GATEWAY = 128;
    uint8 constant CURRENT_VERSION = 1;

    // deployTokens flags 
    uint32 constant MAPPING_ETHEREUM_OWNED = 1;
    uint32 constant MAPPING_VERUS_OWNED = 2;
    uint32 constant MAPPING_PARTOF_BRIDGEVETH = 4;
    uint32 constant MAPPING_ISBRIDGE_CURRENCY = 8;
    uint32 constant TOKEN_ERC20_SEND = 16;
    uint32 constant TOKEN_LAUNCH = 32;
    uint32 constant TOKEN_ETH_SEND = 64;
    uint32 constant TOKEN_ETH_NFT_DEFINITION = 128;

    uint32 constant TICKER_LENGTH_MAX = 4;
    uint8 constant DESTINATION_PLUS_GATEWAY = 68;

    //notary flags
    uint8 constant NOTARY_VALID = 1;
    uint8 constant NOTARY_REVOKED = 2;

    uint constant SATS_TO_WEI_STD = 10000000000;

    enum ContractType {
        TokenManager,
        VerusSerializer,
        VerusProof,
        VerusCrossChainExport,
        VerusNotarizer,
        VerusBridge,
        VerusInfo,
        ExportManager,
        VerusBridgeStorage,
        VerusNotarizerStorage,
        VerusBridgeMaster,
        LastIndex
    }
        
}