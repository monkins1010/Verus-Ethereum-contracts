/**
 * debugCCESourceHeight.js
 *
 * Reproduces the sourceHeightStart == 0 bug for the CCE output hex supplied by
 * the developer.  Run against a local Ganache node:
 *
 *   truffle test test/debugCCESourceHeight.js
 *
 * The test calls checkExportAndTransfers directly with a minimal
 * CReserveTransferImport that wraps the raw CTxOut bytes, then also calls
 * readVarint directly to confirm the varint decoding itself is correct.
 *
 * Expected root cause: _collectExporter does "nextOffset += 1" before calling
 * readAuxDest when FLAG_DEST_AUX (0x40) is set, which skips the aux-dest count
 * byte (0x01) and instead reads the next byte (0x23 = 35) as the count.  The
 * 35-iteration loop consumes far too many bytes, leaving readVarint pointing at
 * zero padding, so sourceHeightStart comes back 0.
 */

const VerusProof = artifacts.require("../contracts/MMR/VerusProof.sol");
const { id }     = require("../migrations/setup.js");

contract("debugCCESourceHeight", async () => {

  // --------------------------------------------------------------------------
  // Raw CTxOut bytes provided by the developer.
  // exporterType = 0x44 = DEST_ETH (0x04) | FLAG_DEST_AUX (0x40)
  // --------------------------------------------------------------------------
  const CCE_TX_OUTPUT_HEX =
    "0x0000000000000000fd40011a04030001011452047d0db35c330271aae70bedce996b5239ca5c" +
    "cc4d200104030c01011452047d0db35c330271aae70bedce996b5239ca5c4d030101008000" +
    "1af5b8015c64d39ab44c60ead8317f9f5a9b6c4c" +       // sourceSystemID  = mainnet VRSC
    "43d51478538c7ce6d29fa4a49ce4e7650c0bb02ee5bc298f181639ccb72eb13d" + // hashRT
    "454cb83913d688795e237837d30258d11ea7c752" +         // destSystemID    = mainnet VETH
    "454cb83913d688795e237837d30258d11ea7c752" +         // destCurrencyID  = mainnet VETH
    "441463bb9f612be23a8f51aad6d62ec8b8342ddba6ac" +    // exporter 0x44, len=0x14, 20-byte addr
    "0123012103dcf755d26e1e8a274bde940e9d242d99fa212e31c090437af86bdd7ec021e1" +
    "10010000000100000080f7b73180f7bc3c01" +             // firstInput / numInputs / VARINTs
    "454cb83913d688795e237837d30258d11ea7c7523b640300000000000" +
    "1454cb83913d688795e237837d30258d11ea7c752bb54fe0200000000" +
    "01454cb83913d688795e237837d30258d11ea7c752bb54fe020000000000" +
    "75";

  // hashReserveTransfers lives at CCE bytes [24..55].
  const HASHED_TRANSFERS =
    "0x43d51478538c7ce6d29fa4a49ce4e7650c0bb02ee5bc298f181639ccb72eb13d";

  // A 36-byte prevout (32-byte zero txid + 4-byte index zero).
  // lastTxid in a fresh deployment is bytes32(0), so prevoutHash == 0 passes.
  const DUMMY_PREVOUT = "0x" + "00".repeat(36);

  // Minimal dummy branch so elProof[0].proofSequence.nIndex is accessible.
  const dummyProof = () => ([{
    branchType: 2,
    proofSequence: {
      CMerkleBranchBase: 0,
      nIndex: 1,
      nSize: 6,
      extraHashes: 0,
      branch: []
    }
  }]);

  const buildMinimalImport = () => ({
    partialtransactionproof: {
      version: 2,
      typeC: 0,
      txproof: [],
      components: [
        // [0] – TX_HEADER placeholder; checkExportAndTransfers loops from i=1.
        { elType: 1, elIdx: 0, elVchObj: "0x00", elProof: [] },

        // [1] – TX_PREVOUTSEQ: sets foundInput=true / inputMatchesLastCCE=true.
        { elType: 2, elIdx: 0, elVchObj: DUMMY_PREVOUT, elProof: [] },

        // [2] – TYPE_TX_OUTPUT: the CCE output to parse.
        { elType: 4, elIdx: 0, elVchObj: CCE_TX_OUTPUT_HEX, elProof: dummyProof() }
      ]
    },
    serializedTransfers: "0x"
  });

  // --------------------------------------------------------------------------
  it("checkExportAndTransfers returns non-zero sourceHeightStart", async () => {
    const vp = await VerusProof.new(
      id.mainnet.VETH,
      id.mainnet.BRIDGE,
      id.mainnet.VRSC
    );

    let result;
    try {
      result = await vp.checkExportAndTransfers.call(
        buildMinimalImport(),
        HASHED_TRANSFERS
      );
    } catch (e) {
      console.log("\n  REVERT:", e.message);
      throw new Error("checkExportAndTransfers reverted: " + e.message);
    }

    const packed   = BigInt(result[0].toString());
    const startH   = Number(packed         & BigInt("0xFFFFFFFF"));
    const endH     = Number((packed >> 32n) & BigInt("0xFFFFFFFF"));
    const nIdx     = Number((packed >> 64n) & BigInt("0xFFFFFFFF"));
    const numIn    = Number((packed >> 96n) & BigInt("0xFFFFFFFF"));

    console.log("\n  packed (hex)     :", "0x" + packed.toString(16).padStart(32, "0"));
    console.log("  sourceHeightStart:", startH);
    console.log("  sourceHeightEnd  :", endH);
    console.log("  nIndex           :", nIdx);
    console.log("  numInputs        :", numIn);
    console.log("  exporter         :", result[1].toString(16));
    console.log("  exporter2        :", result[2].toString(16));
    console.log("  exporter3        :", result[3].toString(16));

    assert.notEqual(startH, 0,
      "sourceHeightStart is 0 — offset bug in _collectExporter FLAG_DEST_AUX branch");
  });

  // --------------------------------------------------------------------------
  // Independently verify readVarint on the expected varint bytes.
  // The varint "80 f7 b7 31" should decode to a non-zero block height ~4 070 449.
  // --------------------------------------------------------------------------
  it("readVarint correctly decodes 0x80 0xf7 0xb7 0x31", async () => {
    const vp = await VerusProof.new(
      id.mainnet.VETH,
      id.mainnet.BRIDGE,
      id.mainnet.VRSC
    );

    // Build a 32-byte buffer with the varint bytes at position 0.
    const buf = "0x80f7b731" + "00".repeat(28);

    // readVarint(buf, idx=0): reads buf[0] first.
    const result = await vp.readVarint(buf, 0);
    const v      = result[0];
    const retidx = result[1];
    console.log("\n  varint(80 f7 b7 31) =", v.toNumber(), "  retidx =", retidx.toNumber());

    // Manual expected decode:
    //   byte 0x80: low7=0,  v=0+1=1 (continuation)
    //   byte 0xf7: low7=0x77=119, v=(1<<7)|119=247, v+1=248
    //   byte 0xb7: low7=0x37=55,  v=(248<<7)|55=31799, v+1=31800
    //   byte 0x31: low7=0x31=49,  v=(31800<<7)|49=4070449  (no continuation)
    assert.equal(v.toNumber(), 4070449, "Expected sourceHeightStart ≈ 4 070 449");
    assert.equal(retidx.toNumber(), 4,  "Expected retidx = 4 (4 varint bytes consumed, last offset = 4)");
  });

});
