const { CurrencyValueMap, ReserveTransfer, TransferDestination } = require("verus-typescript-primitives");
//const  BigNumber  = require("verus-typescript-primitives/dist/utils/types/Bignumber");
var BN = require('bn.js');


const trans_tobuf = new ReserveTransfer({
      values: new CurrencyValueMap({
        value_map: new Map([
          ["iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm", new BN(100000000, 10)]
        ]),
        multivalue: false
      }),
      version: new BN(1, 10),
      flags: new BN(1, 10),
      fee_currency_id: "iJhCezBExJHvtyH3fGhNnt2NhU4Ztkf2yq",
      fee_amount: new BN(2000000, 10),
      transfer_destination: new TransferDestination({
        type: new BN(2, 10),
        destination_bytes: Buffer.from("9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD", 'hex'),
        fees: new BN(0, 10)
      }),
      dest_currency_id: "iJhCezBExJHvtyH3fGhNnt2NhU4Ztkf2yq"
    })

module.exports = trans_tobuf;