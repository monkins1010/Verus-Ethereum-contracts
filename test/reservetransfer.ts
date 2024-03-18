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
const CURRENCY_EXPORT = 0x2000


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
    destination_bytes: Buffer.from("0100000020080000a6ef9ea235635e328124ff3429db9f9e91b64e2d056368616437a6ef9ea235635e328124ff3429db9f9e91b64e2d67460c2f56774ed27eeb8685f29f6cec0b090b0001000000030000004a34f7f25bfc8a4e4a4413243cc5388e5a056cb4235b00000000000000000000000000000000000000000000000000000000000000ff012301210200000000000000000000000000000000000000000000000000000000000000ff00000000000000000000000000000000000000008a9f0000000000000000000000000000000000000001a6ef9ea235635e328124ff3429db9f9e91b64e2d000100000000000000000001000000000000000001000000000000000001000000000000000000000000000000a49faec70003f98800", 'hex'),
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
    destination_bytes: Buffer.from("0100000020000000a6ef9ea235635e328124ff3429db9f9e91b64e2d056368616437a6ef9ea235635e328124ff3429db9f9e91b64e2d67460c2f56774ed27eeb8685f29f6cec0b090b0001000000030000004914f7f25bfc8a4e4a4413243cc5388e5a056cb4235b012301210200000000000000000000000000000000000000000000000000000000000000ff00000000000000000000000000000000000000008a9f1b00000000000000000000000000000000000001a6ef9ea235635e328124ff3429db9f9e91b64e2d000100e1f505000000000001000000000000000001000000000000000001000000000000000000000000000000a49faec70003f98800", 'hex'),
  }),
  dest_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm"
})

const testErcVerus = new ReserveTransfer({  
  values: new CurrencyValueMap({
    value_map: new Map([
      ["iAwycBuMcPJii45bKNTEfSnD9W9iXMiKGg", new BN(0, 10)]  //swap 1 ETH
    ]),
    multivalue: false
  }),
  version: new BN(1, 10),
  flags: new BN(VALID + CROSS_SYSTEM + CURRENCY_EXPORT, 10),   //
  fee_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",  // fee currency veth
  fee_amount: new BN(540000, 10),   // 0.0054 ETH FEE SATS (8 decimal places)
  transfer_destination: new TransferDestination({
    type: new BN(DEST_REGISTERCURRENCY, 10),
    destination_bytes: Buffer.from("0100000020000000a6ef9ea235635e328124ff3429db9f9e91b64e2d0865726332306d6170a6ef9ea235635e328124ff3429db9f9e91b64e2d67460c2f56774ed27eeb8685f29f6cec0b090b0001000000030000000914b897f2448054bc5b133268a53090e110d101fff000000000000000000000000000000000000000008a0600000000000000000000000000000000000001a6ef9ea235635e328124ff3429db9f9e91b64e2d000100e1f505000000000001000000000000000001000000000000000001000000000000000000000000000000a49faec70003f98800", 'hex'),
  }),
  dest_currency_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm",
  dest_system_id: "iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm"
})

const twoReserveTransfers = [verusReserveTransfer, verusReserveTransfer];

const proofinput = [
  {
     "height":341,
     "txid":"0x75ea17c9654f23733a03d25a9c0387956e9c8fdef47ce840474c6513b5a63843",
     "txoutnum":0,
     "exportinfo":{
        "version":1,
        "flags":2,
        "sourcesystemid":"0x67460c2f56774ed27eeb8685f29f6cec0b090b00",
        "hashtransfers":"0xd7281d5bd3e008a0dd2ba12b8760fbe3215087cd3a483f6c0398507f690f7904",
        "destinationsystemid":"0xa6ef9ea235635e328124ff3429db9f9e91b64e2d",
        "destinationcurrencyid":"0x67460c2f56774ed27eeb8685f29f6cec0b090b00",
        "sourceheightstart":1,
        "sourceheightend":2,
        "numinputs":1,
        "totalamounts":[
           {
              "currency":"0x67460c2f56774ed27eeb8685f29f6cec0b090b00",
              "amount":2030000
           }
        ],
        "totalfees":[
           {
              "currency":"0x67460c2f56774ed27eeb8685f29f6cec0b090b00",
              "amount":30000
           }
        ],
        "totalburned":[
           {
              "currency":"0x0000000000000000000000000000000000000000",
              "amount":0
           }
        ],
        "rewardaddress":{
           
        },
        "firstinput":1
     },
     "partialtransactionproof":{
        "version":1,
        "typeC":2,
        "txproof":[
           {
              "branchType":2,
              "proofSequence":{
                 "CMerkleBranchBase":2,
                 "nIndex":1,
                 "nSize":3,
                 "extraHashes":0,
                 "branch":[
                    "0x2c916711a7143497062940f543daf3dcd5900b7fd7da1f8b7523cd6b2071c18a",
                    "0x0000000000000000000000000000000000000000000000000000000000000000"
                 ],
                 "txHeight":1
              }
           },
           {
              "branchType":2,
              "proofSequence":{
                 "CMerkleBranchBase":2,
                 "nIndex":0,
                 "nSize":2,
                 "extraHashes":0,
                 "branch":[
                    "0x54e88762b07838958306fe87ce052ba5f0d8b297c8fbbf53223db5a881000000"
                 ],
                 "txHeight":0
              }
           },
           {
              "branchType":3,
              "proofSequence":{
                 "CMerkleBranchBase":3,
                 "nIndex":2594,
                 "nSize":352,
                 "extraHashes":1,
                 "branch":[
                    "0xc7eae60100000000000000000000000000000000000000000000000000000000",
                    "0xd6dff527c354ecc7168330ef7b9966a50910afb002d4a126591d115f055f7c1b",
                    "0xa302f60300000000000000000000000000000000000000000000000000000000",
                    "0x1daa88fa256b6e879c2797485a2278ea82332cafca0693e22f95a69977dfd78a",
                    "0x1ee6960700000000000000000000000087c7a49db76a14000000000000000000",
                    "0xd605679f5a0272e17503ab04646569402b8a092160a5aa3a4dd71b3e6976ef72",
                    "0xb2aac80f0000000000000000000000001c9f037f589a1f000000000000000000",
                    "0xefc72b3aa715c29af607b122c16d9f086cc5c0b683d3f17fcdc559549d685c14",
                    "0x0bd4e220000000000000000000000000eec57944234640000000000000000000",
                    "0x3a673fe4ee3c97a889846a3fddfe3f8c7e149bafe4481740ceae656427fdebdf",
                    "0x4203f73400000000000000000000000079959cd36e4a9a000000000000000000",
                    "0xc4954a000980058dda5450b30e46ba72649c44df2df8e558e467e3c8475682aa",
                    "0x3241720c020000000000000000000000605acd8192f316020000000000000000"
                 ],
                 "txHeight":341
              }
           }
        ],
        "components":[
           {
              "elType":1,
              "elIdx":0,
              "elVchObj":"0x75ea17c9654f23733a03d25a9c0387956e9c8fdef47ce840474c6513b5a63843010400000085202f890200000001000000000000000000000000000000690100000000000000000000",
              "elProof":[
                 {
                    "branchType":2,
                    "proofSequence":{
                       "CMerkleBranchBase":2,
                       "nIndex":0,
                       "nSize":6,
                       "extraHashes":0,
                       "branch":[
                          "0xf36ab323b97f31ec40f2634c0f3d9bd2b96ada1a46db7b14ca03e85b0651449e",
                          "0x025253b337536886a30c1e3e0cb8f4d7868a0b2772f7dd447039911ab939f310",
                          "0x4156f8d4d3394072fb13b25574becb10a92b830e9aec0e3fe97cf7e1d3a7a814"
                       ],
                       "txHeight":0
                    }
                 }
              ]
           },
           {
              "elType":2,
              "elIdx":0,
              "elVchObj":"0x77fe97c08b114257c7a897e3a3da356033ab612dd1706fd1b193bb74a33a29ac04000000ffffffff",
              "elProof":[
                 {
                    "branchType":2,
                    "proofSequence":{
                       "CMerkleBranchBase":2,
                       "nIndex":1,
                       "nSize":6,
                       "extraHashes":0,
                       "branch":[
                          "0x8aee4690d988f4a81b6575ea25a25e03381105b4312ca0b710d0bbd3e71ef1ed",
                          "0x025253b337536886a30c1e3e0cb8f4d7868a0b2772f7dd447039911ab939f310",
                          "0x4156f8d4d3394072fb13b25574becb10a92b830e9aec0e3fe97cf7e1d3a7a814"
                       ],
                       "txHeight":1
                    }
                 }
              ]
           },
           {
              "elType":4,
              "elIdx":0,
              "elVchObj":"0x0000000000000000f91a04030001011452047d0db35c330271aae70bedce996b5239ca5ccc4cda04030c01011452047d0db35c330271aae70bedce996b5239ca5c4cbe01008000a6ef9ea235635e328124ff3429db9f9e91b64e2dd7281d5bd3e008a0dd2ba12b8760fbe3215087cd3a483f6c0398507f690f790467460c2f56774ed27eeb8685f29f6cec0b090b0067460c2f56774ed27eeb8685f29f6cec0b090b0002144e6f51cf16700e4edb9390ed42912e3498ec26050100000001000000811e8154000167460c2f56774ed27eeb8685f29f6cec0b090b00b0f91e00000000000167460c2f56774ed27eeb8685f29f6cec0b090b00b0f91e00000000000075",
              "elProof":[
                 {
                    "branchType":2,
                    "proofSequence":{
                       "CMerkleBranchBase":2,
                       "nIndex":3,
                       "nSize":6,
                       "extraHashes":0,
                       "branch":[
                          "0x5a1d4bd7301a5da460525637c0ae9042bc3dc7c7c6eaab350bfbb1f9d0e56a7c",
                          "0xbb038091d3f2fac7bec99c72d776f506cc13667820f92b1a3726c70773c0db99"
                       ],
                       "txHeight":5
                    }
                 }
              ]
           }
        ]
     },
     "transfers":[
        {
           "version":1,
           "flags":65,
           "crosssystem":true,
           "feecurrencyid":"0x67460c2f56774ed27eeb8685f29f6cec0b090b00",
           "fees":30000,
           "destination":{
              "destinationaddress":"0x37245c7f865b5c1b6f1db81523ccf3626df625bc",
              "destinationtype":9
           },
           "secondreserveid":"0x0000000000000000000000000000000000000000",
           "currencyvalue":{
              "currency":"0x67460c2f56774ed27eeb8685f29f6cec0b090b00",
              "amount":2000000
           },
           "destcurrencyid":"0x67460c2f56774ed27eeb8685f29f6cec0b090b00",
           "destsystemid":"0x67460c2f56774ed27eeb8685f29f6cec0b090b00"
        }
     ],
     "serializedTransfers":"0x0167460c2f56774ed27eeb8685f29f6cec0b090b00f988004167460c2f56774ed27eeb8685f29f6cec0b090b0080e930091437245c7f865b5c1b6f1db81523ccf3626df625bc67460c2f56774ed27eeb8685f29f6cec0b090b0067460c2f56774ed27eeb8685f29f6cec0b090b00"
  }
]


const invalidComponents = []


module.exports.invalidComponents = invalidComponents;
module.exports.proofinput = proofinput;

module.exports.prelaunchfundETH = prelaunchfundETH;
module.exports.bounceback = bounceback;
module.exports.twoReserveTransfers = twoReserveTransfers;
module.exports.erc721transferETH = erc721transferETH;
module.exports.erc721transferVerus = erc721transferVerus;
module.exports.erc20verustoken = erc20verustoken;
module.exports.erc20ETHtoken = erc20ETHtoken;
module.exports.erc1155VerusNFT = erc1155VerusNFT;
module.exports.erc1155Token = erc1155Token;
module.exports.testErcVerus = testErcVerus;