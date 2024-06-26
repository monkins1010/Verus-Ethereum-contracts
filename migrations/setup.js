const MAPPING_ETHEREUM_OWNED = 1;
const MAPPING_VERUS_OWNED = 2;
const MAPPING_PARTOF_BRIDGEVETH = 4;
const MAPPING_ISBRIDGE_CURRENCY = 8;
const MAPPING_ERC20_DEFINITION = 32;

// These are the mainnet notaries iaddresses in hex form.
const verusMainnetNotariserIDS = [];

// These are the equivelent ETH mainnet addresses of the notaries Spending R addresses
const verusMainnetNotariserSigner = [];

// These are the equivelent ETH mainnet addresses of the notaries Recovery R addresses
const verusMainnetNotariserRecovery = [];

// These are the notaries Sepolia iaddresses in hex form.
const verusSepoliaNotariserIDS = [];

// These are the equivelent ETH Sepolia addresses of the notaries Spending R addresses
const verusSepoliaNotariserSigner = [];

// These are the equivelent ETH Sepolia addresses of the notaries Recovery R addresses
const verusSepoliaNotariserRecovery = [];

// These are the development notaries iaddresses in hex form.
const TestVerusNotariserIDS = [
    "0xb26820ee0c9b1276aac834cf457026a575dfce84", 
    "0x51f9f5f053ce16cb7ca070f5c68a1cb0616ba624", 
    "0x65374d6a8b853a5f61070ad7d774ee54621f9638"];

// These are the equivelent ETH development addresses of the notaries Spending R addresses
const TestVerusNotariserSigner = [
    "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", 
    "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", 
    "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41"];

// These are the equivelent ETH development addresses of the notaries Recovery R addresses
const TestVerusNotariserRecovery = [
    "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", 
    "0xD3258AD271066B7a780C68e527A6ee69ecA15b7F", 
    "0x68f56bA248E23b7d5DE4Def67592a1366431d345"];

const getNotarizerIDS = (network) => {

    if (network == "development"){
        return [TestVerusNotariserIDS, TestVerusNotariserSigner, TestVerusNotariserRecovery];
    } else if (network == "sepolia" || network == "sepolia-fork"){
        return [verusSepoliaNotariserIDS, verusSepoliaNotariserSigner, verusSepoliaNotariserRecovery];
    } else if (network == "mainnet" || network == "mainnet-fork"){
        return [verusMainnetNotariserIDS, verusMainnetNotariserSigner, verusMainnetNotariserRecovery];
    }
}

// Verus ID's in uint160 format and ERC20s.
const id = {  
    mainnet: {
        VETH: "0x454CB83913D688795E237837d30258d11ea7c752",
        VRSC: "0x1Af5b8015C64d39Ab44C60EAd8317f9F5a9B6C4C",
        BRIDGE: "0x0200EbbD26467B866120D84A0d37c82CdE0acAEB",
        DAI: "0x8b72F1c2D326d376aDd46698E385Cf624f0CA1dA",
        DAIERC20: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
        MKR: "0x65b5aac6a4aa0eb656ab6b8812184e7545b6a221",
        MKRERC20: "0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2",
        DAIPOT: "0x197e90f9fad81970ba7976f33cbd77088e5d7cf7",
        DAIJOIN: "0x9759A6Ac90977b93B58547b4A71c78317f391A28",
    },
    testnet: {
        VETH: "0x67460C2f56774eD27EeB8685f29f6CEC0B090B00",
        VRSC: "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d",
        BRIDGE: "0xffEce948b8A38bBcC813411D2597f7f8485a0689",
        DAI: "0xcce5d18f305474f1e0e0ec1c507d8c85e7315fdf",
        DAIERC20: "0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844", //NOTE: Testnet DAI on maintestnet is 0xB897f2448054bc5b133268A53090e110D101FFf0
        DAIPOT: "0x50672F0a14B40051B65958818a7AcA3D54Bd81Af",
        DAIJOIN: "0x6a60b7070befb2bfc964F646efDF70388320f4E0",
        MKR: "0x005005b2b10a897fed36fbd71c878213a7a169bf" , 
        MKRERC20: "0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2"  // TODO: Change this to testnet MKR
    },
    emptyuint160: "0x0000000000000000000000000000000000000000",
    emptyuint256: "0x0000000000000000000000000000000000000000000000000000000000000000"
}

const returnConstructorCurrencies = (isTestnet = false) => {

    return [
        isTestnet ? id.testnet.VETH : id.mainnet.VETH,
        isTestnet ? id.testnet.BRIDGE : id.mainnet.BRIDGE,
        isTestnet ? id.testnet.VRSC : id.mainnet.VRSC
    ]
}

const getDAI = (isTestnet = false) => {
    return isTestnet ? id.testnet.DAI : id.mainnet.DAI;
}

const getMKR = (isTestnet = false) => {
    return isTestnet ? id.testnet.MKR : id.mainnet.MKR;
}

const getDSRMANAGER = (isTestnet = false) => {

    const retval = {DSRJOIN: isTestnet ? id.testnet.DAIJOIN : id.mainnet.DAIJOIN, DSRPOT: isTestnet ? id.testnet.DAIPOT : id.mainnet.DAIPOT}
    return retval;
}

const getDAIERC20Address = (isTestnet = false) => {
    return isTestnet ? id.testnet.DAIERC20 : id.mainnet.DAIERC20;
}
// currencies that are defined are in this format:
// iaddress in hex, ERC20 contract, parent, token options, name, ticker, NFTtokenID.
const returnSetupCurrencies = (isTestnet = false) => {

    //NOTE: IMPORTANT THIS ORDER MATTERS. DO NOT CHANGE IT. ONLY ADD TO THE END.
    
    const vrsc = [
        isTestnet ? id.testnet.VRSC : id.mainnet.VRSC,
        id.emptyuint160, 
        id.emptyuint160, 
        MAPPING_VERUS_OWNED + MAPPING_PARTOF_BRIDGEVETH + MAPPING_ERC20_DEFINITION, 
        isTestnet ? "VRSCTEST" : "VRSC",
        "VRSC",
        id.emptyuint256];
        
    const bridgeeth = [
        isTestnet ? id.testnet.BRIDGE : id.mainnet.BRIDGE,
        id.emptyuint160, 
        isTestnet ? id.testnet.VRSC : id.mainnet.VRSC,
        MAPPING_VERUS_OWNED + MAPPING_ISBRIDGE_CURRENCY + MAPPING_ERC20_DEFINITION, 
        "Bridge.vETH", 
        "VBRID",
        id.emptyuint256];
        
    const veth = [
        isTestnet ? id.testnet.VETH : id.mainnet.VETH,
        id.emptyuint160,
        isTestnet ? id.testnet.VRSC : id.mainnet.VRSC,
        MAPPING_ETHEREUM_OWNED + MAPPING_PARTOF_BRIDGEVETH + MAPPING_ERC20_DEFINITION, 
        isTestnet ? "ETH (Testnet)" : "vETH", 
        "vETH",
        id.emptyuint256];

    const dai = [
        isTestnet ? id.testnet.DAI : id.mainnet.DAI,
        isTestnet ? id.testnet.DAIERC20 : id.mainnet.DAIERC20,
        isTestnet ? id.testnet.VRSC : id.mainnet.VRSC, 
        MAPPING_ETHEREUM_OWNED + MAPPING_PARTOF_BRIDGEVETH + MAPPING_ERC20_DEFINITION, 
        isTestnet ? "DAI (Testnet)" : "DAI.vETH", 
        "DAI",
        id.emptyuint256];

    const mkr = [
        isTestnet ? id.testnet.MKR : id.mainnet.MKR,
        isTestnet ? id.testnet.MKRERC20 : id.mainnet.MKRERC20,
        isTestnet ? id.testnet.VRSC : id.mainnet.VRSC, 
        MAPPING_ETHEREUM_OWNED + MAPPING_PARTOF_BRIDGEVETH + MAPPING_ERC20_DEFINITION, 
        isTestnet ? "Maker (Testnet)" : "MKR.vETH", 
        "MKR",
        id.emptyuint256];

    // Add new currencies here.

    return [vrsc, bridgeeth, veth, dai, mkr];
}

exports.id = id;
exports.getNotarizerIDS = getNotarizerIDS;
exports.arrayofcurrencies = returnSetupCurrencies;
exports.returnConstructorCurrencies = returnConstructorCurrencies;
exports.getDAI = getDAI;
exports.getMKR = getMKR;
exports.getDSRMANAGER = getDSRMANAGER;  
exports.getDAIERC20Address = getDAIERC20Address;