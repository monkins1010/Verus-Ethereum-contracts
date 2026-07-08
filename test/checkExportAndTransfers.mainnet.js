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

    // Expect a non-zero packed value when CCE fields are accepted.
    assert.notEqual(result[0].toString(), "0", "Expected non-zero packed result");
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
