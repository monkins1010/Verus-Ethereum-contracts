const Web3 = require('web3');
var UpgradeManager = artifacts.require("./VerusBridge/UpgradeManager.sol");
var VerusBridgeMaster = artifacts.require("./VerusBridge/VerusBridgeMaster.sol");
var VerusBridgeStorage = artifacts.require("./VerusBridge/VerusBridgeStorage.sol");
var VerusNotarizerStorage = artifacts.require("./VerusNotarizer/VerusNotarizerStorage.sol");
var VerusTokenManager = artifacts.require("./VerusBridge/TokenManager.sol");
var VerusSerializer = artifacts.require("./VerusBridge/VerusSerializer.sol");
var VerusNotarizer = artifacts.require("./VerusNotarizer/VerusNotarizer.sol");
var VerusProof = artifacts.require("./MMR/VerusProof.sol");
var VerusCCE = artifacts.require("./VerusBridge/VerusCrossChainExport.sol");
var VerusBridge = artifacts.require("./VerusBridge/VerusBridge.sol");
var NotarizationSerializer = artifacts.require("./VerusNotarizer/NotarizationSerializer.sol");
var VerusInfo = artifacts.require("./VerusBridge/VerusInfo.sol");
var ExportManager = artifacts.require("./VerusBridge/ExportManager.sol");
var VerusBlake2b = artifacts.require("./MMR/VerusBlake2b.sol");
var VerusMMR = artifacts.require("./MMR/VerusMMR.sol");

// QUESTION: remove all hard coded values like those below (tokenmanvrsctest, etc.) and put them in config or parameters
// What is the most correct approach / actual best practice?
const MAPPING_ETHEREUM_OWNED = 1;
const MAPPING_VERUS_OWNED = 2;
const MAPPING_PARTOF_BRIDGEVETH = 4;
const MAPPING_ISBRIDGE_CURRENCY = 8;
const TOKEN_LAUNCH = 32;
const verusNotariserIDS = ["0xb26820ee0c9b1276aac834cf457026a575dfce84", "0x51f9f5f053ce16cb7ca070f5c68a1cb0616ba624", "0x65374d6a8b853a5f61070ad7d774ee54621f9638"];
const verusNotariserSigner = ["0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41"];
const verusNotariserRevoker = ["0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", "0xD3258AD271066B7a780C68e527A6ee69ecA15b7F", "0x68f56bA248E23b7d5DE4Def67592a1366431d345"];
const tokenmanvrsctest = ["0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", "0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000", MAPPING_VERUS_OWNED + MAPPING_PARTOF_BRIDGEVETH + TOKEN_LAUNCH, "vrsctest", "VRSC","0x0000000000000000000000000000000000000000000000000000000000000000"];
const tokenmanbeth = ["0xffEce948b8A38bBcC813411D2597f7f8485a0689", "0x0000000000000000000000000000000000000000", "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", MAPPING_VERUS_OWNED + MAPPING_ISBRIDGE_CURRENCY + TOKEN_LAUNCH, "bridge.vETH", "BETH","0x0000000000000000000000000000000000000000000000000000000000000000"];
const tokenmanUSDC = ["0xf0a1263056c30e221f0f851c36b767fff2544f7f", "0x98339D8C260052B7ad81c28c16C0b98420f2B46a", "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", MAPPING_ETHEREUM_OWNED + MAPPING_PARTOF_BRIDGEVETH + TOKEN_LAUNCH, "Testnet USDC", "USDC","0x0000000000000000000000000000000000000000000000000000000000000000"];
const vETH = ["0x67460C2f56774eD27EeB8685f29f6CEC0B090B00", "0x06012c8cf97bead5deae237070f9587f8e7a266d", "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", MAPPING_ETHEREUM_OWNED + MAPPING_PARTOF_BRIDGEVETH + TOKEN_LAUNCH, "Testnet ETH", "ETH","0x0000000000000000000000000000000000000000000000000000000000000000"];


module.exports = async function(deployer) {

    let block = await web3.eth.getBlock("latest");

    await deployer.deploy(UpgradeManager);
    const UpgradeInst = await UpgradeManager.deployed();

    await deployer.deploy(VerusBridgeMaster, UpgradeInst.address);
    const bridgeMasterInst = await VerusBridgeMaster.deployed();

    await deployer.deploy(VerusBridgeStorage, UpgradeInst.address); //5000 VRSC in sats
    const bridgeStorageInst = await VerusBridgeStorage.deployed();

    await deployer.deploy(VerusNotarizerStorage, UpgradeInst.address);
    const NotarizerStorageInst = await VerusNotarizerStorage.deployed();

    await deployer.deploy(VerusBlake2b);
    await VerusBlake2b.deployed();

    await deployer.deploy(VerusSerializer);
    const serializerInst = await VerusSerializer.deployed();

    await deployer.deploy(NotarizationSerializer, UpgradeInst.address, serializerInst.address );
    const notarizationSerializerInst = await NotarizationSerializer.deployed();

    await deployer.deploy(VerusTokenManager, UpgradeInst.address, bridgeStorageInst.address, serializerInst.address)
    const tokenInst = await VerusTokenManager.deployed();

    await deployer.link(VerusBlake2b, VerusNotarizer);
    await deployer.deploy(VerusNotarizer, serializerInst.address, UpgradeInst.address, verusNotariserIDS, verusNotariserSigner, verusNotariserRevoker, NotarizerStorageInst.address, bridgeMasterInst.address, notarizationSerializerInst.address);
    const notarizerInst = await VerusNotarizer.deployed();

    await deployer.deploy(VerusMMR);
    await VerusMMR.deployed();
    await deployer.link(VerusMMR, VerusProof);
    await deployer.link(VerusBlake2b, VerusProof);
    await deployer.deploy(VerusProof, UpgradeInst.address, serializerInst.address, notarizerInst.address);
    const ProofInst = await VerusProof.deployed();

    await deployer.deploy(VerusCCE, serializerInst.address, UpgradeInst.address);
    const CCEInst = await VerusCCE.deployed();

    await deployer.deploy(ExportManager, bridgeStorageInst.address, tokenInst.address, UpgradeInst.address);
    const ExportManInst = await ExportManager.deployed();

    await deployer.deploy(VerusBridge, bridgeMasterInst.address, bridgeStorageInst.address, tokenInst.address, serializerInst.address, ProofInst.address, CCEInst.address, ExportManInst.address, UpgradeInst.address, block.number, "500000000000");
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
        bridgeMasterInst.address,
        notarizationSerializerInst.address

    ];

    try {
        await UpgradeInst.setInitialContracts(allContracts);
        let launchCurrencies = [tokenmanvrsctest, tokenmanbeth, tokenmanUSDC, vETH];
        await INFOInst.launchContractTokens(launchCurrencies);

        const settingString = "\nupgrademanageraddress=" + UpgradeInst.address + "\n\n" +
            "export const BRIDGE_MASTER_ADD = \"" + bridgeMasterInst.address + "\";\n" +
            "export const BRIDGE_STORAGE_ADD = \"" + bridgeStorageInst.address + "\";\n" +
            "export const UPGRADE_ADD = \"" + UpgradeInst.address + "\";\n" +
            "export const TOKEN_MANAGER_ADD = \"" + tokenInst.address + "\";\n";
    
        console.log("Settings to be pasted into *.conf file and website \n\n", settingString);
        
    } catch (e) {

        console.log(e);

    }

};