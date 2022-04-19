var UpgradeManager = artifacts.require("./VerusBridge/UpgradeManager.sol");
var VerusBridgeMaster = artifacts.require("./VerusBridge/VerusBridgeMaster.sol");
var VerusBridgeStorage = artifacts.require("./VerusBridge/VerusBridgeStorage.sol");
var VerusNotarizerStorage = artifacts.require("./VerusNotarizer/VerusNotarizerStorage.sol");
var VerusTokenManager = artifacts.require("./VerusBridge/TokenManager.sol");
var VerusBlake2b = artifacts.require("./MMR/VerusBlake2b.sol");
var VerusSerializer = artifacts.require("./VerusBridge/VerusSerializer.sol");
var VerusNotarizer = artifacts.require("./VerusNotarizer/VerusNotarizer.sol");
var VerusProof = artifacts.require("./MMR/VerusProof.sol");
var VerusCCE = artifacts.require("./VerusBridge/VerusCrossChainExport.sol");
var VerusBridge = artifacts.require("./VerusBridge/VerusBridge.sol");
var Verusaddress = artifacts.require("./VerusBridge/VerusAddressCalculator.sol");
var VerusInfo = artifacts.require("./VerusBridge/VerusInfo.sol");
var Token = artifacts.require("./VerusBridge/Token.sol");
var ExportManager = artifacts.require("./VerusBridge/ExportManager.sol");

// QUESTION: remove all hard coded values like those below (tokenmanvrsctest, etc.) and put them in config or parameters
// What is the most correct approach / actual best practice?
const MAPPING_ETHEREUM_OWNED = 1;
const MAPPING_VERUS_OWNED = 2;
const MAPPING_PARTOF_BRIDGEVETH = 4;
const MAPPING_ISBRIDGE_CURRENCY = 8;
const verusNotariserIDS = ["0xb26820ee0c9b1276aac834cf457026a575dfce84", "0x51f9f5f053ce16cb7ca070f5c68a1cb0616ba624", "0x65374d6a8b853a5f61070ad7d774ee54621f9638"];
const verusNotariserSigner = ["0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41"];
const tokenmanvrsctest = ["0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", "0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000", MAPPING_VERUS_OWNED + MAPPING_PARTOF_BRIDGEVETH, "vrsctest", "VRSC"];
const tokenmanbeth = ["0xffEce948b8A38bBcC813411D2597f7f8485a0689", "0x0000000000000000000000000000000000000000", "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", MAPPING_VERUS_OWNED + MAPPING_ISBRIDGE_CURRENCY, "bridge.vETH", "BETH"];
const tokenmanUSDC = ["0xf0a1263056c30e221f0f851c36b767fff2544f7f", "0xeb8f08a975ab53e34d8a0330e0d34de942c95926", "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", MAPPING_ETHEREUM_OWNED + MAPPING_PARTOF_BRIDGEVETH, "Rinkeby USDC", "USDC"];
const vETH = ["0x67460C2f56774eD27EeB8685f29f6CEC0B090B00", "0x06012c8cf97bead5deae237070f9587f8e7a266d", "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", MAPPING_ETHEREUM_OWNED + MAPPING_PARTOF_BRIDGEVETH, "Rinkeby ETH", "ETH"];

const launchCurrencies = [tokenmanvrsctest, tokenmanbeth, tokenmanUSDC, vETH];

const USDCERC20 = "0xeb8f08a975ab53e34d8a0330e0d34de942c95926";

module.exports = async function(deployer) {

    await deployer.deploy(UpgradeManager);
    const UpgradeInst = await UpgradeManager.deployed();

    await deployer.deploy(VerusBridgeMaster, UpgradeInst.address);
    const bridgeMasterInst = await VerusBridgeMaster.deployed();

    await deployer.deploy(VerusBridgeStorage, UpgradeInst.address, "5000000000000000000000");
    const bridgeStorageInst = await VerusBridgeStorage.deployed();

    await deployer.deploy(VerusNotarizerStorage, UpgradeInst.address);
    const NotarizerStorageInst = await VerusNotarizerStorage.deployed();

    await deployer.deploy(VerusBlake2b);
    const blakeInst = await VerusBlake2b.deployed();

    await deployer.deploy(VerusSerializer);
    const serializerInst = await VerusSerializer.deployed();

    await deployer.deploy(VerusTokenManager, UpgradeInst.address, bridgeStorageInst.address, serializerInst.address, bridgeMasterInst.address)
    const tokenInst = await VerusTokenManager.deployed();

    await deployer.deploy(VerusNotarizer, blakeInst.address, serializerInst.address, UpgradeInst.address, verusNotariserIDS, verusNotariserSigner, NotarizerStorageInst.address, bridgeMasterInst.address);
    const notarizerInst = await VerusNotarizer.deployed();

    await deployer.deploy(VerusProof, UpgradeInst.address, blakeInst.address, serializerInst.address, NotarizerStorageInst.address);
    const ProofInst = await VerusProof.deployed();

    await deployer.deploy(VerusCCE, serializerInst.address, UpgradeInst.address);
    const CCEInst = await VerusCCE.deployed();

    await deployer.deploy(ExportManager, bridgeStorageInst.address, tokenInst.address, UpgradeInst.address);
    const ExportManInst = await ExportManager.deployed();

    await deployer.deploy(VerusBridge, bridgeMasterInst.address, bridgeStorageInst.address, tokenInst.address, serializerInst.address, ProofInst.address, CCEInst.address, ExportManInst.address, UpgradeInst.address);
    const VerusBridgeInst = await VerusBridge.deployed();

    await deployer.deploy(VerusInfo, notarizerInst.address, "2000753", "0.7.3-9-rc1", "VETH", true, UpgradeInst.address, tokenInst.address);
    const INFOInst = await VerusInfo.deployed();

    const allContracts = [
        tokenInst.address,
        serializerInst.address,
        ProofInst.address,
        CCEInst.address,
        notarizerInst.address,
        VerusBridgeInst.address,
        INFOInst.address,
        ExportManInst.address,
        bridgeStorageInst.address,
        NotarizerStorageInst.address,
        bridgeMasterInst.address

    ];

    try {
        await UpgradeInst.setInitialContracts(allContracts);
        await INFOInst.launchTokens(launchCurrencies);

    } catch (e) {

        console.log(e);

    }

    let USDCInst = await Token.at(USDCERC20);

    USDCInst.increaseAllowance(VerusBridgeInst.address, "1000000000000000000000000");

    const settingString = "\nverusbridgeaddress=" + bridgeMasterInst.address + "\n" +
        "storageaddress=" + bridgeStorageInst.address + "\n\n" +
        "export const BRIDGE_MASTER_ADD = \"" + bridgeMasterInst.address + "\";\n" +
        "export const BRIDGE_STORAGE_ADD = \"" + bridgeStorageInst.address + "\";\n" +
        "export const UPGRADE_ADD = \"" + UpgradeInst.address + "\";\n";

    console.log("Settings to be pasted into *.conf file and website \n\n", settingString);
};