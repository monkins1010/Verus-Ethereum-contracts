// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

// Developers notes for datatypes used:
// uint176 types are used to store CTransferDestiantions as we are limited to a type (1byte) + vector length (1byte) + 20 bytes address.
// These are used to allow the contract to process up to 50 transactions per CCE.  When a currency import enters the contract through a transaction
// The destination is a bytes array.


library VerusConstants {
    address constant public VEth = 0x67460C2f56774eD27EeB8685f29f6CEC0B090B00;
    address constant public VerusSystemId = 0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d;
    address constant public VerusCurrencyId = 0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d;
    address constant public VerusUSDCId = 0xF0A1263056c30E221F0F851C36b767ffF2544f7F;
    address constant public VerusBridgeAddress = 0xffEce948b8A38bBcC813411D2597f7f8485a0689;
    address constant public VerusNFTID = 0x9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD;
    uint256 constant public transactionFee = 3000000000000000; //0.003 ETH 18 decimals
    uint256 constant public upgradeFee = 1000000000000000; //0.001 ETH 18 decimals WEI  TODO: increase for MAINNET
    uint64 constant public verusTransactionFee = 2000000; //0.02 VRSC 8 decimals
    uint64 constant public verusvETHTransactionFee = 300000; //0.003 vETH 8 decimals
    uint64 constant public verusvETHReturnFee = 1000000; //0.01 vETH 8 decimals
    uint64 constant public verusBridgeLaunchFeeShare = 500000000000;
    uint32 constant VALID = 1;
    uint32 constant CONVERT = 2;
    uint32 constant CROSS_SYSTEM = 0x40; 
    uint32 constant BURN_CHANGE_PRICE = 0x80;              
    uint32 constant IMPORT_TO_SOURCE = 0x200;          
    uint32 constant RESERVE_TO_RESERVE = 0x400; 
    uint32 constant CURRENCY_EXPORT = 0x2000;

    uint32 constant INVALID_FLAGS = 0xffffffff - (VALID + CONVERT + RESERVE_TO_RESERVE + IMPORT_TO_SOURCE);

    uint8 constant DEST_PKH = 2;
    uint8 constant DEST_SH = 3;
    uint8 constant DEST_ID = 4;
    uint8 constant DEST_REGISTERCURRENCY = 6;
    uint8 constant DEST_ETH = 9;
    uint8 constant DEST_ETHNFT = 10;
    uint8 constant FLAG_DEST_AUX = 64;
    uint8 constant FLAG_DEST_GATEWAY = 128;
    uint8 constant CURRENT_VERSION = 1;

    // deploy & launch Token flags These must match the constants in deploycontracts.js
    uint32 constant MAPPING_ETHEREUM_OWNED = 1;
    uint32 constant MAPPING_VERUS_OWNED = 2;
    uint32 constant MAPPING_PARTOF_BRIDGEVETH = 4;
    uint32 constant MAPPING_ISBRIDGE_CURRENCY = 8;
    uint32 constant TOKEN_ERC20_SEND = 16;   //TODO: Make these tokens down to a new set
    uint32 constant TOKEN_LAUNCH = 32;
    uint32 constant TOKEN_ETH_SEND = 64;
    uint32 constant TOKEN_ETH_NFT_DEFINITION = 128;  //TODO: this should be part of mapping

    uint32 constant AUX_DEST_PREFIX = 0x01160214;

    uint32 constant TICKER_LENGTH_MAX = 4;
    uint8 constant DESTINATION_PLUS_GATEWAY = 68;

    //notary flags
    uint8 constant NOTARY_VALID = 1;
    uint8 constant NOTARY_REVOKED = 2;

    //notarizationflags
    uint32 constant FLAG_CONTRACT_UPGRADE = 0x200;

    //cCurrencydefintion constants
    uint32 constant OPTION_NFT_TOKEN = 0x800;

    uint constant SATS_TO_WEI_STD = 10000000000;
    uint8 constant NUMBER_OF_CONTRACTS = 11;
    uint64 constant MIN_VRSC_FEE = 4000000; //0.04 VRSC 8 decimals
    uint64 constant MAX_VERUS_TRANSFER = 1000000000000000000; //10,000,000,000.00000000

    enum ContractType {
        TokenManager,
        VerusSerializer,
        VerusProof,
        VerusCrossChainExport,
        VerusNotarizer,
        CreateExport,
        VerusNotaryTools,
        ExportManager,
        SubmitImports,
        NotarizationSerializer,
        UpgradeManager
    } 

    uint8 constant UINT160_SIZE = 20;
    uint8 constant UINT64_SIZE = 8;
    uint8 constant UINT176_BITS_SIZE = 176;
    uint8 constant UINT160_BITS_SIZE = 160;

    //Global Generic Variable types

    uint8 constant GLOBAL_TYPE_NOTARY_ADDRESS = 1;
    bytes constant GLOBAL_TYPE_NOTARY_INVALID = hex'00';
    bytes constant GLOBAL_TYPE_NOTARY_VALID = hex'01';
}

//TODO: extra constants to add 176, 92 etc..
//NOTE: Check constants with Mike

