const { CurrencyValueMap, ReserveTransfer, TransferDestination } = require("verus-typescript-primitives");
//const  BigNumber  = require("verus-typescript-primitives/dist/utils/types/Bignumber");
var BN = require('bn.js');

const DEST_PKH = 2
const DEST_ID = 4
const DEST_ETH = 9
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

module.exports.prelaunchfundETH = prelaunchfundETH;
module.exports.bounceback = bounceback;