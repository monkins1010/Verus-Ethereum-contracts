const VerusProof = artifacts.require("../contracts/MMR/VerusProof.sol");
const { id } = require("../migrations/setup.js");
const goodTx = require("./goodtransaction.json");

contract("VerusProof mainnet checkExportAndTransfers", async () => {
  // Extracted from the known-good CCE payload in test/goodtransaction.json.
  const HASHED_TRANSFERS = "0xf37999ebc168d9109aa536b0773e82da0c4b86ce11e701a7792922b5bb2c4142";

  const buildImportInput = () => JSON.parse(JSON.stringify(goodTx.input.data));

  it("accepts mainnet goodtransaction in checkExportAndTransfers", async () => {
    const verusProof = await VerusProof.new(
      id.mainnet.VETH,
      id.mainnet.BRIDGE,
      id.mainnet.VRSC
    );

    const mainInput = buildImportInput();

    const result = await verusProof.checkExportAndTransfers.call(mainInput, HASHED_TRANSFERS);

    const packed   = BigInt(result[0].toString());
    const startH   = Number(packed         & BigInt("0xFFFFFFFF"));
    const endH     = Number((packed >> 32n) & BigInt("0xFFFFFFFF"));
    const numIn    = Number((packed >> 96n) & BigInt("0xFFFFFFFF"));

    console.log("\n  packed (hex)     :", "0x" + packed.toString(16).padStart(32, "0"));
    console.log("  sourceHeightStart:", startH);
    console.log("  sourceHeightEnd  :", endH);
    console.log("  numInputs        :", numIn);
    console.log("  exporter         :", result[1].toString(16));
    console.log("  exporter2        :", result[2].toString(16));
    console.log("  exporter3        :", result[3].toString(16));

    // CCE varint "80 f7 b3 12" decodes to 4 069 906.
    assert.equal(startH, 4069906,  "sourceHeightStart mismatch");
    // CCE varint "80 f7 b7 30" decodes to 4 070 448.
    assert.equal(endH,   4070448,  "sourceHeightEnd mismatch");
    assert.equal(numIn,  1,        "numInputs mismatch");

    // exporter: type(0x44) + compact-size(0x14) + 20-byte address = uint176
    assert.equal(
      result[1].toString(16).padStart(44, "0"),
      "441463bb9f612be23a8f51aad6d62ec8b8342ddba6ac",
      "exporter (addr1) mismatch"
    );
    // exporter2: aux-dest entry is exactly AUX_DEST_ETH_VEC_LENGTH (22) bytes
    assert.equal(
      result[2].toString(16).padStart(44, "0"),
      "021444a5b8ead66bba58d568c684ae8910541d4ac4fc",
      "exporter2 (aux-dest addr) mismatch"
    );
    // exporter3: only one aux-dest entry, so zero
    assert.equal(result[3].toString(), "0", "exporter3 should be zero");
  });

  it("reverts when CCE nVersion is changed from 1 to 0", async () => {
    const verusProof = await VerusProof.new(
      id.mainnet.VETH,
      id.mainnet.BRIDGE,
      id.mainnet.VRSC
    );

    const mainInput = buildImportInput();
    const outputComponent = mainInput.partialtransactionproof.components.find((c) => c.elType === 4);

    assert.isOk(outputComponent, "Missing TX output component");

    // In CCE bytes: nVersion(0x0100 LE) followed by flags(0x8000 LE).
    // Mutate only the first nVersion pattern we find to 0x0000 while keeping flags intact.
    const marker = "01008000";
    const idx = outputComponent.elVchObj.indexOf(marker);
    assert.isAtLeast(idx, 0, "Could not locate nVersion+flags marker in elVchObj");

    outputComponent.elVchObj =
      outputComponent.elVchObj.slice(0, idx) +
      "00008000" +
      outputComponent.elVchObj.slice(idx + marker.length);

    try {
      await verusProof.checkExportAndTransfers.call(mainInput, HASHED_TRANSFERS);
      assert.fail("Expected revert for invalid CCE nVersion");
    } catch (e) {
      assert.include(e.message, "CCE nVersion must be 1");
    }
  });

  it("reverts when CCE flags are changed from 0x8000 to 0x8400", async () => {
    const verusProof = await VerusProof.new(
      id.mainnet.VETH,
      id.mainnet.BRIDGE,
      id.mainnet.VRSC
    );

    const mainInput = buildImportInput();
    const outputComponent = mainInput.partialtransactionproof.components.find((c) => c.elType === 4);

    assert.isOk(outputComponent, "Missing TX output component");

    // nVersion stays 0x0100 LE, mutate only flags from 0x8000 to 0x8400.
    const marker = "01008000";
    const idx = outputComponent.elVchObj.indexOf(marker);
    assert.isAtLeast(idx, 0, "Could not locate nVersion+flags marker in elVchObj");

    outputComponent.elVchObj =
      outputComponent.elVchObj.slice(0, idx) +
      "01008400" +
      outputComponent.elVchObj.slice(idx + marker.length);

    try {
      await verusProof.checkExportAndTransfers.call(mainInput, HASHED_TRANSFERS);
      assert.fail("Expected revert for invalid CCE flags 0x8400");
    } catch (e) {
      assert.include(e.message, "revert");
    }
  });
});
