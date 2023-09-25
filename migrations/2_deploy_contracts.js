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

let globalDAI = null;

const { returnConstructorCurrencies, 
    arrayofcurrencies,
    getNotarizerIDS,
    getDAI,
    getDSRMANAGER,
    getDAIERC20Address } = setup;
    
module.exports = async function(deployer) {
        
    const isTestnet = deployer.network == "development" || deployer.network == "goerli" || deployer.network == "goerli-fork";
    
    const currencyConstants = returnConstructorCurrencies(isTestnet);
    const DAI = getDAI(isTestnet);
    const DSRMANAGER = getDSRMANAGER(isTestnet);
    let DAIERC20 = getDAIERC20Address(isTestnet);
    const launchCurrencies = await getCurrencies(deployer);
    
    if (deployer.network == "development") { 

        DAIERC20 = globalDAI;
    }
    
    await deployer.deploy(UpgradeManager);
    const UpgradeInst = await UpgradeManager.deployed();
    
    await deployer.deploy(VerusBlake2b);
    await VerusBlake2b.deployed();
    
    await deployer.deploy(VerusSerializer, ...currencyConstants);
    const serializerInst = await VerusSerializer.deployed();
    
    await deployer.deploy(NotarizationSerializer, ...currencyConstants, DAI);
    const notarizationSerializerInst = await NotarizationSerializer.deployed();
    
    await deployer.deploy(VerusTokenManager, ...currencyConstants, DAIERC20, DSRMANAGER)
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


    await deployer.deploy(CreateExports, ...currencyConstants, DAI, DSRMANAGER, DAIERC20);
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


    await VerusDelegatorInst.launchContractTokens(launchCurrencies);

    const settingString = "\ndelegatorcontractaddress=" + VerusDelegatorInst.address + "\n\n" +
        "export const DELEGATOR_ADD = \"" + VerusDelegatorInst.address + "\";";

    console.log("\nSettings to be pasted into *.conf file and website constants \n", settingString);        
};

const getCurrencies = async (deployer) => {
    
    // if testnetERC is not null then we are running ganache test and need to replace the DAI address with the testnetERC address.
    let isTestnet = deployer.network == "development" || deployer.network == "goerli" || deployer.network == "goerli-fork"
    let currencies = arrayofcurrencies(isTestnet);

    if (deployer.network == "development"){
        
        await deployer.deploy(Token, "DAI (Testnet)", "DAI");
        const TokenInst = await Token.deployed();
        TokenInst.mint(deployer.networks.goerli.from, "100000000000000000000000");
        console.log("\nDAI DEPLOYED\n", TokenInst.address); 
        currencies[3][1] = TokenInst.address;
        globalDAI = TokenInst.address;
    } 

    if (deployer.network == "development" || deployer.network == "goerli" || deployer.network == "goerli-fork") {

        await deployer.deploy(Token, "MKR (Testnet)", "MKR"); //TODO: Replace if there is an offical Goerli ERC20 MKR
        const TokenInst = await Token.deployed();
        TokenInst.mint(deployer.networks.goerli.from, "100000000000000000000000");
        console.log("\nMKR DEPLOYED\n", TokenInst.address); 
        currencies[4][1] = TokenInst.address;
    }

    let data = abi.encodeParameter(
        'tuple(address,address,address,uint8,string,string,uint256)[]',
        currencies);

    return data;
}
