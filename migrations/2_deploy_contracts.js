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
var Token = artifacts.require("./VerusBridge/Token.sol");

const abi = web3.eth.abi

const { verusNotariserIDS, 
        verusNotariserSigner, 
        verusNotariserRecovery,
        TestVerusNotariserIDS,
        TestVerusNotariserSigner,
        TestVerusNotariserRecovery,
        returnConstructorCurrencies, 
        arrayofcurrencies,
        getNotarizerIDS } = setup;

module.exports = async function(deployer) {

    const currencyConstants = returnConstructorCurrencies(deployer.network == "development" || deployer.network == "goerli");

    await deployer.deploy(UpgradeManager);
    const UpgradeInst = await UpgradeManager.deployed();

    await deployer.deploy(VerusBlake2b);
    await VerusBlake2b.deployed();

    await deployer.deploy(VerusSerializer, ...currencyConstants);
    const serializerInst = await VerusSerializer.deployed();

    await deployer.deploy(NotarizationSerializer, ...currencyConstants);
    const notarizationSerializerInst = await NotarizationSerializer.deployed();

    await deployer.deploy(VerusTokenManager, ...currencyConstants)
    const tokenInst = await VerusTokenManager.deployed();

    await deployer.link(VerusBlake2b, VerusNotarizer);
    await deployer.deploy(VerusNotarizer, ...currencyConstants);
    const notarizerInst = await VerusNotarizer.deployed();

    await deployer.deploy(VerusMMR);
    await VerusMMR.deployed();
    await deployer.link(VerusMMR, VerusProof);
    await deployer.link(VerusBlake2b, VerusProof);
    await deployer.deploy(VerusProof, ...currencyConstants);
    const ProofInst = await VerusProof.deployed();

    await deployer.deploy(VerusCCE, ...currencyConstants);
    const CCEInst = await VerusCCE.deployed();

    await deployer.deploy(ExportManager, ...currencyConstants);
    const ExportManInst = await ExportManager.deployed();

    await deployer.deploy(CreateExports, ...currencyConstants);
    const CreateExportsInst = await CreateExports.deployed();

    await deployer.deploy(SubmitImports, ...currencyConstants);
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

    const notarizerIDS = getNotarizerIDS(deployer.network)

    await deployer.deploy(VerusDelegator, ...notarizerIDS, allContracts);

    const VerusDelegatorInst = await VerusDelegator.deployed();

    let testnetERC = null;
    if (deployer.network == "development"){
        
        await deployer.deploy(Token, "DAI (Testnet)", "DAI");
        const TokenInst = await Token.deployed();
        testnetERC = TokenInst.address;
        console.log("\nDAI DEPLOYED\n", TokenInst.address); 
    } 
    const launchCurrencies = getCurrencies(testnetERC);

    await VerusDelegatorInst.launchContractTokens(launchCurrencies);

    const settingString = "\ndelegatorcontractaddress=" + VerusDelegatorInst.address + "\n\n" +
        "export const DELEGATOR_ADD = \"" + VerusDelegatorInst.address + "\";";

    console.log("\nSettings to be pasted into *.conf file and website constants \n", settingString);        
};

const getCurrencies = (testnetERC) => {
    
    // if testnetERC is not null then we are running ganache test and need to replace the DAI address with the testnetERC address.
    let currencies = arrayofcurrencies(testnetERC != null);

    if(testnetERC){
        // if running ganache test replace contract with adhoc one.
        currencies[3][1] = testnetERC;
    }

    let data = abi.encodeParameter(
        'tuple(address,address,address,uint8,string,string,uint256)[]',
        currencies);

    return data;
}
