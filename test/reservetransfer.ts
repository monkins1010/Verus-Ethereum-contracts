const { CurrencyValueMap, ReserveTransfer, TransferDestination } = require("verus-typescript-primitives");
//const  BigNumber  = require("verus-typescript-primitives/dist/utils/types/Bignumber");
var BN = require('bn.js');

const DEST_PKH = 2
const DEST_ID = 4
const DEST_ETH = 9
const DEST_REGISTERCURRENCY = 6
const FLAG_DEST_AUX = 64
const FLAG_DEST_GATEWAY = 128
const VALID = 1
const CONVERT = 2
const PRECONVERT = 4
const CROSS_SYSTEM = 0x40           
const IMPORT_TO_SOURCE = 0x200          
const RESERVE_TO_RESERVE = 0x400  


const prelaunchfundETH = new ReserveTransfer({
      values: new CurrencyValueMap({
        value_map: new Map([
          ["iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm", new BN(100000000, 10)]
        ]),
        multivalue: false
      }),
      version: new BN(1, 10),
      flags: new BN(VALID, 10),
      fee_currency_id: "iJhCezBExJHvtyH3fGhNnt2NhU4Ztkf2yq", // fee currency vrsctest
      fee_amount: new BN(2000000, 10),
      transfer_destination: new TransferDestination({
        type: new BN(2, 10),
        destination_bytes: Buffer.from("9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD", 'hex'),
        fees: new BN(0, 10)
      }),
      dest_currency_id: "iJhCezBExJHvtyH3fGhNnt2NhU4Ztkf2yq"
    })

const bounceback = new ReserveTransfer({  // The bridge currency has to be launched for this TX ETH -> VRSCTEST back to ETH address
    values: new CurrencyValueMap({
      value_map: new Map([
        ["iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm", new BN(100000000, 10)]  //swap 1 ETH
      ]),
      multivalue: false
    }),
    version: new BN(1, 10),
    flags: new BN(VALID + CONVERT + RESERVE_TO_RESERVE, 10),   //
    fee_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",  // fee currency veth
    fee_amount: new BN(300000, 10),   // 0.003 ETH FEE SATS (8 decimal places)
    transfer_destination: new TransferDestination({
      type: new BN(DEST_ETH + FLAG_DEST_AUX + FLAG_DEST_GATEWAY, 10),
      destination_bytes: Buffer.from("9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD", 'hex'),
      gateway_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",
      fees: new BN(300000, 10),
      aux_dests:[new TransferDestination({
        type: new BN(DEST_PKH, 10),
        destination_bytes: Buffer.from("9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD", 'hex')})]
    }),
    dest_currency_id: "iSojYsotVzXz4wh2eJriASGo6UidJDDhL2",
    second_reserve_id: "iJhCezBExJHvtyH3fGhNnt2NhU4Ztkf2yq"
  })


    //run definecurrency '{"name":"chad7","options":2080,"systemid":"veth","parent":"vrsctest","currencies":["VRSCTEST"],
    //"launchsystemid":"vrsctest","nativecurrencyid":{"type":10,"address": {"contract": "0x39Ec448b891c476e166b3C3242A90830DB556661",
    //"tokenid":"0x00000000000000000000000000000000000000000000000000000000000000ff"}},"maxpreconversion":[0],"initialsupply":0,"proofprotocol":3}'

const verusReserveTransfer = new ReserveTransfer({  // The bridge currency has to be launched for this TX ETH -> VRSCTEST back to ETH address
  values: new CurrencyValueMap({
    value_map: new Map([
      ["iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm", new BN(100000000, 10)]  //swap 1 ETH
    ]),
    multivalue: false
  }),
  version: new BN(1, 10),
  flags: new BN(VALID, 10),   //
  fee_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",  // fee currency veth
  fee_amount: new BN(300000, 10),   // 0.003 ETH FEE SATS (8 decimal places)
  transfer_destination: new TransferDestination({
    type: new BN(DEST_ETH + FLAG_DEST_AUX, 10),
    destination_bytes: Buffer.from("9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD", 'hex'),
    aux_dests:[new TransferDestination({
      type: new BN(DEST_PKH, 10),
      destination_bytes: Buffer.from("9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD", 'hex')})]
  }),
  dest_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm"
})

    //run definecurrency '{"name":"chad7","options":2080,"preallocations":[{"chad7@":0.00000001}],"maxpreconversion":[0]}'

const erc721transferETH = new ReserveTransfer({  
  values: new CurrencyValueMap({
    value_map: new Map([
      ["i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ", new BN(0, 10)]  //swap 1 ETH
    ]),
    multivalue: false
  }),
  version: new BN(1, 10),
  flags: new BN(VALID, 10),   //
  fee_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",  // fee currency veth
  fee_amount: new BN(300000, 10),   // 0.003 ETH FEE SATS (8 decimal places)
  transfer_destination: new TransferDestination({
    type: new BN(DEST_REGISTERCURRENCY, 10),
    destination_bytes: Buffer.from("0100000020080000a6ef9ea235635e328124ff3429db9f9e91b64e2d056368616437a6ef9ea235635e328124ff3429db9f9e91b64e2d67460c2f56774ed27eeb8685f29f6cec0b090b0001000000030000000a3439ec448b891c476e166b3c3242a90830db55666100000000000000000000000000000000000000000000000000000000000000ff00000000000000000000000000000000000000008a8e0d00000000000000000000000000000000000001a6ef9ea235635e328124ff3429db9f9e91b64e2d000100000000000000000001000000000000000001000000000000000001000000000000000000000000000000a49faec70003f98800", 'hex'),
  }),
  dest_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm"
})

const erc721transferVerus = new ReserveTransfer({ 
  values: new CurrencyValueMap({
    value_map: new Map([
      ["i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ", new BN(0, 10)]  //swap 1 ETH
    ]),
    multivalue: false
  }),
  version: new BN(1, 10),
  flags: new BN(VALID, 10),   //
  fee_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",  // fee currency veth
  fee_amount: new BN(300000, 10),   // 0.003 ETH FEE SATS (8 decimal places)
  transfer_destination: new TransferDestination({
    type: new BN(DEST_REGISTERCURRENCY, 10),
    destination_bytes: Buffer.from("0100000020080000a6ef9ea235635e328124ff3429db9f9e91b64e2d056368616437a6ef9ea235635e328124ff3429db9f9e91b64e2da6ef9ea235635e328124ff3429db9f9e91b64e2d0100000001000000000000000000000000000000000000000000000000008a9351000000000000000000012c0d13af98a412ad79e77cfdee70bac119b054fa0100000000000000000000000000000001a6ef9ea235635e328124ff3429db9f9e91b64e2d000100000000000000000001000000000000000001000000000000000001000000000000000000000000000000a49faec70003f98800", 'hex'),
  }),
  dest_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm"
})

const erc20verustoken = new ReserveTransfer({ 
  values: new CurrencyValueMap({
    value_map: new Map([
      ["i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ", new BN(0, 10)]  //swap 1 ETH
    ]),
    multivalue: false
  }),
  version: new BN(1, 10),
  flags: new BN(VALID, 10),   //
  fee_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",  // fee currency veth
  fee_amount: new BN(300000, 10),   // 0.003 ETH FEE SATS (8 decimal places)
  transfer_destination: new TransferDestination({
    type: new BN(DEST_REGISTERCURRENCY, 10),
    destination_bytes: Buffer.from("0100000020000000a6ef9ea235635e328124ff3429db9f9e91b64e2d056368616437a6ef9ea235635e328124ff3429db9f9e91b64e2da6ef9ea235635e328124ff3429db9f9e91b64e2d0100000001000000000000000000000000000000000000000000000000008a9451000000000000000000012c0d13af98a412ad79e77cfdee70bac119b054fa0080ca396124000000000000000000000000000000000000000000000000a49faec70003f98800", 'hex'),
  }),
  dest_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm"
})

const erc20ETHtoken = new ReserveTransfer({  
  values: new CurrencyValueMap({
    value_map: new Map([
      ["i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ", new BN(0, 10)]  //swap 1 ETH
    ]),
    multivalue: false
  }),
  version: new BN(1, 10),
  flags: new BN(VALID, 10),   //
  fee_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",  // fee currency veth
  fee_amount: new BN(300000, 10),   // 0.003 ETH FEE SATS (8 decimal places)
  transfer_destination: new TransferDestination({
    type: new BN(DEST_REGISTERCURRENCY, 10),
    destination_bytes: Buffer.from("0100000020000000a6ef9ea235635e328124ff3429db9f9e91b64e2d056368616437a6ef9ea235635e328124ff3429db9f9e91b64e2d67460c2f56774ed27eeb8685f29f6cec0b090b0001000000030000000914b897f2448054bc5b133268a53090e110d101fff000000000000000000000000000000000000000008a953e00000000000000000000000000000000000001a6ef9ea235635e328124ff3429db9f9e91b64e2d000100e1f505000000000001000000000000000001000000000000000001000000000000000000000000000000a49faec70003f98800", 'hex'),
  }),
  dest_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm"
})

//
const erc1155VerusNFT = new ReserveTransfer({  
  values: new CurrencyValueMap({
    value_map: new Map([
      ["iAwycBuMcPJii45bKNTEfSnD9W9iXMiKGg", new BN(0, 10)]  //swap 1 ETH
    ]),
    multivalue: false
  }),
  version: new BN(1, 10),
  flags: new BN(VALID, 10),   //
  fee_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",  // fee currency veth
  fee_amount: new BN(300000, 10),   // 0.003 ETH FEE SATS (8 decimal places)
  transfer_destination: new TransferDestination({
    type: new BN(DEST_REGISTERCURRENCY, 10),
    destination_bytes: Buffer.from("0100000020080000a6ef9ea235635e328124ff3429db9f9e91b64e2d03696432a6ef9ea235635e328124ff3429db9f9e91b64e2d67460c2f56774ed27eeb8685f29f6cec0b090b0001000000030000004a34f7f25bfc8a4e4a4413243cc5388e5a056cb4235b00000000000000000000000000000000000000000000000000000000000000ff01360a34f7f25bfc8a4e4a4413243cc5388e5a056cb4235b00000000000000000000000000000000000000000000000000000000000000ff0000000000000000000000000000000000000000895900000000000000000000000000000000000001a6ef9ea235635e328124ff3429db9f9e91b64e2d000100000000000000000001000000000000000001000000000000000001000000000000000000000000000000a49faec70003f98800", 'hex'),
  }),
  dest_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm"
})

const erc1155Token = new ReserveTransfer({  
  values: new CurrencyValueMap({
    value_map: new Map([
      ["iAwycBuMcPJii45bKNTEfSnD9W9iXMiKGg", new BN(0, 10)]  //swap 1 ETH
    ]),
    multivalue: false
  }),
  version: new BN(1, 10),
  flags: new BN(VALID, 10),   //
  fee_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",  // fee currency veth
  fee_amount: new BN(300000, 10),   // 0.003 ETH FEE SATS (8 decimal places)
  transfer_destination: new TransferDestination({
    type: new BN(DEST_REGISTERCURRENCY, 10),
    destination_bytes: Buffer.from("0100000020000000a6ef9ea235635e328124ff3429db9f9e91b64e2d03696432a6ef9ea235635e328124ff3429db9f9e91b64e2d67460c2f56774ed27eeb8685f29f6cec0b090b0001000000030000004914f7f25bfc8a4e4a4413243cc5388e5a056cb4235b01360a34f7f25bfc8a4e4a4413243cc5388e5a056cb4235b00000000000000000000000000000000000000000000000000000000000000ff0000000000000000000000000000000000000000895900000000000000000000000000000000000001a6ef9ea235635e328124ff3429db9f9e91b64e2d000100e1f505000000000001000000000000000001000000000000000001000000000000000000000000000000a49faec70003f98800", 'hex'),
  }),
  dest_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm"
})

const twoReserveTransfers = [verusReserveTransfer, verusReserveTransfer];

module.exports.prelaunchfundETH = prelaunchfundETH;
module.exports.bounceback = bounceback;
module.exports.twoReserveTransfers = twoReserveTransfers;
module.exports.erc721transferETH = erc721transferETH;
module.exports.erc721transferVerus = erc721transferVerus;
module.exports.erc20verustoken = erc20verustoken;
module.exports.erc20ETHtoken = erc20ETHtoken;
module.exports.erc1155VerusNFT = erc1155VerusNFT;
module.exports.erc1155Token = erc1155Token;