const Web3 = require('web3');
const setup = require('./setup.js');
var UpgradeManager = artifacts.require("./VerusBridge/UpgradeManager.sol");
var VerusTokenManager = artifacts.require("./VerusBridge/TokenManager.sol");
var VerusSerializer = artifacts.require("./VerusBridge/VerusSerializer.sol");
var VerusNotarizer = artifacts.require("./VerusNotarizer/VerusNotarizer.sol");
var VerusProof = artifacts.require("./MMR/VerusProof.sol");
var VerusCCE = artifacts.require("./VerusBridge/VerusCrossChainExport.sol");
var CreateExports = artifacts.require("./VerusBridge/CreateExports.sol");
var SubmitImports = artifacts.require("./VerusBridge/SubmitImports.sol");
var NotarizationSerializer = artifacts.require("./VerusNotarizer/NotarizationSerializer.sol");
var VerusNotaryTools = artifacts.require("./VerusNotarizer/NotaryTools.sol");
var ExportManager = artifacts.require("./VerusBridge/ExportManager.sol");
var VerusBlake2b = artifacts.require("./MMR/VerusBlake2b.sol");
var VerusMMR = artifacts.require("./MMR/VerusMMR.sol");
var VerusDelegator = artifacts.require("./Main/Delegator.sol");

const abi = web3.eth.abi

const verusNotariserIDS = setup.verusNotariserIDS;
const verusNotariserSigner = setup.verusNotariserSigner;
const verusNotariserRecovery = setup.verusNotariserRecovery;

module.exports = async function(deployer) {

    await deployer.deploy(UpgradeManager);
    const UpgradeInst = await UpgradeManager.deployed();

    await deployer.deploy(VerusBlake2b);
    await VerusBlake2b.deployed();

    await deployer.deploy(VerusSerializer);
    const serializerInst = await VerusSerializer.deployed();

    await deployer.deploy(NotarizationSerializer);
    const notarizationSerializerInst = await NotarizationSerializer.deployed();

    await deployer.deploy(VerusTokenManager)
    const tokenInst = await VerusTokenManager.deployed();

    await deployer.link(VerusBlake2b, VerusNotarizer);
    await deployer.deploy(VerusNotarizer);
    const notarizerInst = await VerusNotarizer.deployed();

    await deployer.deploy(VerusMMR);
    await VerusMMR.deployed();
    await deployer.link(VerusMMR, VerusProof);
    await deployer.link(VerusBlake2b, VerusProof);
    await deployer.deploy(VerusProof);
    const ProofInst = await VerusProof.deployed();

    await deployer.deploy(VerusCCE);
    const CCEInst = await VerusCCE.deployed();

    await deployer.deploy(ExportManager);
    const ExportManInst = await ExportManager.deployed();

    await deployer.deploy(CreateExports);
    const CreateExportsInst = await CreateExports.deployed();

    await deployer.deploy(SubmitImports);
    const SubmitImportsInst = await SubmitImports.deployed();

    await deployer.deploy(VerusNotaryTools);
    const VerusNotaryToolsInst = await VerusNotaryTools.deployed();
    
    const allContracts = [
        tokenInst.address,
        serializerInst.address,
        ProofInst.address,
        CCEInst.address,
        notarizerInst.address,
        CreateExportsInst.address,
        VerusNotaryToolsInst.address,
        ExportManInst.address,
        SubmitImportsInst.address,
        notarizationSerializerInst.address,
        UpgradeInst.address
    ];

    await deployer.deploy(VerusDelegator, verusNotariserIDS, verusNotariserSigner, verusNotariserRecovery, allContracts);
    const VerusDelegatorInst = await VerusDelegator.deployed();

    const launchCurrencies = abidata();
    await VerusDelegatorInst.launchContractTokens(launchCurrencies);

    const settingString = "\ndelegatorcontractaddress=" + VerusDelegatorInst.address + "\n\n" +
        "export const DELEGATOR_ADD = \"" + VerusDelegatorInst.address + "\";";

    console.log("Settings to be pasted into *.conf file and website constants \n\n", settingString);        
};

const abidata = () => {
    
    let arrayofcurrencies = setup.arrayofcurrencies;

    let data = abi.encodeParameter(
        'tuple(address,address,address,uint8,string,string,uint256)[]',
        arrayofcurrencies);

    return data;
}
