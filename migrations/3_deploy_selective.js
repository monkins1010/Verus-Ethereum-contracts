/**
 * Selective contract deployment script.
 *
 * Use the DEPLOY_CONTRACTS environment variable to specify which contracts to
 * deploy by their ContractType enum index (from VerusConstants.sol).
 *
 * ContractType enum:
 *   0  – TokenManager
 *   1  – VerusSerializer
 *   2  – VerusProof
 *   3  – VerusCrossChainExport
 *   4  – VerusNotarizer
 *   5  – CreateExport
 *   6  – VerusNotaryTools
 *   7  – ExportManager
 *   8  – SubmitImports
 *   9  – NotarizationSerializer
 *  10  – UpgradeManager
 *
 * Examples:
 *   DEPLOY_CONTRACTS=0,3,7 truffle migrate --f 3 --to 3 --network mainnet
 *   DEPLOY_CONTRACTS=0,3,7 truffle migrate --f 3 --to 3 --network mainnet --dry-run
 *
 * If DELEGATOR_ADDRESS is set, each freshly deployed contract will also be
 * registered with the Delegator via replacecontract().
 */

const setup = require('./setup.js');
const Web3 = require('web3');

// ── contract artifacts ──────────────────────────────────────────────────────
var UpgradeManager     = artifacts.require("./VerusBridge/UpgradeManager.sol");
var VerusTokenManager  = artifacts.require("./VerusBridge/TokenManager.sol");
var VerusSerializer    = artifacts.require("./VerusBridge/VerusSerializer.sol");
var VerusNotarizer     = artifacts.require("./VerusNotarizer/VerusNotarizer.sol");
var VerusProof         = artifacts.require("./MMR/VerusProof.sol");
var VerusCCE           = artifacts.require("./VerusBridge/VerusCrossChainExport.sol");
var CreateExports      = artifacts.require("./VerusBridge/CreateExports.sol");
var SubmitImports      = artifacts.require("./VerusBridge/SubmitImports.sol");
var NotarizationSerializer = artifacts.require("./VerusNotarizer/NotarizationSerializer.sol");
var VerusNotaryTools   = artifacts.require("./VerusNotarizer/NotaryTools.sol");
var ExportManager      = artifacts.require("./VerusBridge/ExportManager.sol");
var VerusBlake2b       = artifacts.require("./MMR/VerusBlake2b.sol");
var VerusMMR           = artifacts.require("./MMR/VerusMMR.sol");
var VerusDelegator     = artifacts.require("./Main/Delegator.sol");
var Token              = artifacts.require("./VerusBridge/Token.sol");
var MockDaiJoin        = artifacts.require("MockDaiJoin");
var MockPot            = artifacts.require("MockPot");

// ── ContractType enum (mirrors VerusConstants.sol) ─────────────────────────
const CONTRACT_NAMES = [
    "TokenManager",           // 0
    "VerusSerializer",        // 1
    "VerusProof",             // 2
    "VerusCrossChainExport",  // 3
    "VerusNotarizer",         // 4
    "CreateExport",           // 5
    "VerusNotaryTools",       // 6
    "ExportManager",          // 7
    "SubmitImports",          // 8
    "NotarizationSerializer", // 9
    "UpgradeManager",         // 10
];

const abi = web3.eth.abi;
let globalDAI = null;

const {
    returnConstructorCurrencies,
    arrayofcurrencies,
    getNotarizerIDS,
    getDAI,
    getMKR,
    getDSRMANAGER,
    getDAIERC20Address,
} = setup;

// ── helpers ─────────────────────────────────────────────────────────────────

/**
 * Parse the DEPLOY_CONTRACTS env var into a sorted, deduplicated array of
 * integer indices.  Throws if the variable is missing or any index is out of
 * range.
 */
function parseDeployIndices() {
    const raw = process.env.DEPLOY_CONTRACTS;
    if (!raw) {
        throw new Error(
            "DEPLOY_CONTRACTS env var is required.\n" +
            "Example: DEPLOY_CONTRACTS=0,3,7 truffle migrate --f 3 --to 3 --network mainnet"
        );
    }

    const indices = [...new Set(
        raw.split(",").map(s => {
            const n = parseInt(s.trim(), 10);
            if (isNaN(n) || n < 0 || n >= CONTRACT_NAMES.length) {
                throw new Error(
                    `Invalid contract index "${s.trim()}". Valid range: 0–${CONTRACT_NAMES.length - 1}.`
                );
            }
            return n;
        })
    )].sort((a, b) => a - b);

    return indices;
}

// ── main migration ───────────────────────────────────────────────────────────

module.exports = async function(deployer, network, accounts) {

    const indices = parseDeployIndices();
    const deploySet = new Set(indices);

    console.log("\n=== Selective deployment ===");
    console.log("Contracts to deploy:", indices.map(i => `[${i}] ${CONTRACT_NAMES[i]}`).join(", "));
    console.log("Network:", network);

    const isTestnet = network === "development" || network === "sepolia" || network === "sepolia-fork";
    const currencyConstants = returnConstructorCurrencies(isTestnet);
    const DAI   = getDAI(isTestnet);
    const MKR   = getMKR(isTestnet);
    let { DSRPOT, DSRJOIN } = getDSRMANAGER(isTestnet);
    let DAIERC20 = getDAIERC20Address(isTestnet);

    // ── Ganache-specific token setup (mirrors 2_deploy_contracts.js) ─────────
    if (network === "development") {
        // Deploy DAI mock if any contract that needs it is being deployed
        const needsDAI = deploySet.has(0) || deploySet.has(1) || deploySet.has(3) ||
                         deploySet.has(5) || deploySet.has(8) || deploySet.has(9);
        const needsMKR = deploySet.has(1) || deploySet.has(8) || deploySet.has(9);

        if (needsDAI && !globalDAI) {
            await deployer.deploy(Token, "DAI (Testnet)", "DAI");
            const daiInst = await Token.deployed();
            await daiInst.mint(accounts[0], "100000000000000000000000");
            console.log("\nDAI DEPLOYED:", daiInst.address);
            globalDAI = daiInst.address;
        }
        if (globalDAI) DAIERC20 = globalDAI;

        await deployer.deploy(MockDaiJoin, DAIERC20);
        const mockDaiJoinInst = await MockDaiJoin.deployed();
        await deployer.deploy(MockPot);
        const mockPotInst = await MockPot.deployed();
        DSRJOIN = mockDaiJoinInst.address;
        DSRPOT  = mockPotInst.address;
        console.log("Mock DSR deployed – DSRJOIN:", DSRJOIN, "DSRPOT:", DSRPOT);
    }

    if ((network === "development" || network === "sepolia" || network === "sepolia-fork") && !globalDAI) {
        // MKR mock (no DAI needed but MKR might be)
        const needsMKR = deploySet.has(1) || deploySet.has(8) || deploySet.has(9);
        if (needsMKR) {
            await deployer.deploy(Token, "MKR (Testnet)", "MKR");
            const mkrInst = await Token.deployed();
            await mkrInst.mint(accounts[0], "100000000000000000000000");
            console.log("\nMKR DEPLOYED:", mkrInst.address);
        }
    }

    // ── Library deployment (deploy only when needed by a selected contract) ──
    let blake2bDeployed = false;
    let mmrDeployed     = false;

    const needsBlake2b = deploySet.has(2) || deploySet.has(4); // VerusProof, VerusNotarizer
    const needsMMR     = deploySet.has(2);                     // VerusProof

    if (needsBlake2b) {
        await deployer.deploy(VerusBlake2b);
        await VerusBlake2b.deployed();
        blake2bDeployed = true;
        console.log("VerusBlake2b library deployed");
    }

    if (needsMMR) {
        await deployer.deploy(VerusMMR);
        await VerusMMR.deployed();
        mmrDeployed = true;
        console.log("VerusMMR library deployed");
    }

    // ── Per-contract deployment ───────────────────────────────────────────────
    const deployed = {}; // index → { name, address }

    // [0] TokenManager
    if (deploySet.has(0)) {
        await deployer.deploy(VerusTokenManager, ...currencyConstants, DAIERC20);
        const inst = await VerusTokenManager.deployed();
        deployed[0] = { name: CONTRACT_NAMES[0], address: inst.address };
    }

    // [1] VerusSerializer
    if (deploySet.has(1)) {
        await deployer.deploy(VerusSerializer, ...currencyConstants);
        const inst = await VerusSerializer.deployed();
        deployed[1] = { name: CONTRACT_NAMES[1], address: inst.address };
    }

    // [2] VerusProof  (requires Blake2b + MMR libraries)
    if (deploySet.has(2)) {
        await deployer.link(VerusMMR,     VerusProof);
        await deployer.link(VerusBlake2b, VerusProof);
        await deployer.deploy(VerusProof, ...currencyConstants);
        const inst = await VerusProof.deployed();
        deployed[2] = { name: CONTRACT_NAMES[2], address: inst.address };
    }

    // [3] VerusCrossChainExport
    if (deploySet.has(3)) {
        await deployer.deploy(VerusCCE, ...currencyConstants, DAIERC20, DSRPOT, DSRJOIN);
        const inst = await VerusCCE.deployed();
        deployed[3] = { name: CONTRACT_NAMES[3], address: inst.address };
    }

    // [4] VerusNotarizer  (requires Blake2b library)
    if (deploySet.has(4)) {
        await deployer.link(VerusBlake2b, VerusNotarizer);
        await deployer.deploy(VerusNotarizer, ...currencyConstants);
        const inst = await VerusNotarizer.deployed();
        deployed[4] = { name: CONTRACT_NAMES[4], address: inst.address };
    }

    // [5] CreateExport
    if (deploySet.has(5)) {
        await deployer.deploy(CreateExports, ...currencyConstants, DAI, DAIERC20);
        const inst = await CreateExports.deployed();
        deployed[5] = { name: CONTRACT_NAMES[5], address: inst.address };
    }

    // [6] VerusNotaryTools
    if (deploySet.has(6)) {
        await deployer.deploy(VerusNotaryTools);
        const inst = await VerusNotaryTools.deployed();
        deployed[6] = { name: CONTRACT_NAMES[6], address: inst.address };
    }

    // [7] ExportManager
    if (deploySet.has(7)) {
        await deployer.deploy(ExportManager, ...currencyConstants);
        const inst = await ExportManager.deployed();
        deployed[7] = { name: CONTRACT_NAMES[7], address: inst.address };
    }

    // [8] SubmitImports
    if (deploySet.has(8)) {
        await deployer.deploy(SubmitImports, ...currencyConstants, DAI, MKR);
        const inst = await SubmitImports.deployed();
        deployed[8] = { name: CONTRACT_NAMES[8], address: inst.address };
    }

    // [9] NotarizationSerializer
    if (deploySet.has(9)) {
        await deployer.deploy(NotarizationSerializer, ...currencyConstants, DAI, MKR);
        const inst = await NotarizationSerializer.deployed();
        deployed[9] = { name: CONTRACT_NAMES[9], address: inst.address };
    }

    // [10] UpgradeManager
    if (deploySet.has(10)) {
        await deployer.deploy(UpgradeManager);
        const inst = await UpgradeManager.deployed();
        deployed[10] = { name: CONTRACT_NAMES[10], address: inst.address };
    }

    // ── Summary ──────────────────────────────────────────────────────────────
    console.log("\n=== Deployed contract addresses ===");
    for (const [idx, info] of Object.entries(deployed)) {
        console.log(`  [${idx}] ${info.name.padEnd(22)} ${info.address}`);
    }

    // ── Optional: register with Delegator ────────────────────────────────────
    const delegatorAddress = process.env.DELEGATOR_ADDRESS;
    if (delegatorAddress) {
        console.log("\nDELEGATOR_ADDRESS detected – calling replacecontract() for each deployed contract …");
        const delegatorInst = await VerusDelegator.at(delegatorAddress);
        for (const [idx, info] of Object.entries(deployed)) {
            console.log(`  replacecontract(${info.address}, ${idx}) …`);
            await delegatorInst.replacecontract(info.address, parseInt(idx), { gas: 4700000 });
            console.log(`  ✓ [${idx}] ${info.name} registered`);
        }
    } else {
        console.log("\nTip: set DELEGATOR_ADDRESS=<addr> to auto-register contracts with the Delegator.");
    }

    console.log("\n=== Selective deployment complete ===\n");
};
