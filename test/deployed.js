const VerusBridgeMaster = artifacts.require("./VerusBridge/VerusBridgeMaster.sol");
const VerusTokenManager = artifacts.require("./VerusBridge/TokenManager.sol");
const VerusBridgeStorage = artifacts.require("./VerusBridge/VerusBridgeStorage.sol");
const Token = artifacts.require("./VerusBridge/Token.sol");

const abi = require('web3-eth-abi');
const tx = require('../tx.json');
const TokenAbi = require('../build/contracts/ERC20.json');

contract("Verus Contracts deployed tests", async accounts => {

    it("getinfo should return veth & version 2000735", async() => {
        const instance = await VerusBridgeMaster.deployed();
        const info = await instance.getinfo.call();

        let decodedParams = abi.decodeParameters(
            ['uint256', 'string', 'uint256', 'uint256', 'string', 'bool'],
            "0x" + info.slice(66));

        globalgetinfo = {
            "version": decodedParams[0],
            "name": decodedParams[4],
            "VRSCversion": decodedParams[1],
            "blocks": decodedParams[2],
            "tiptime": decodedParams[3],
            "testnet": decodedParams[5],
        }
        assert.equal(globalgetinfo.name, "VETH");
        assert.equal(globalgetinfo.version, '2000753');
    });

    it("Currencies Deployed", async() => {
        const TokenInst = await VerusTokenManager.deployed();
        const tokens = await TokenInst.getTokenList.call();

        assert.equal(tokens.length, 4);
    });

    it("Should send 10 USDC to contract", async() => {
        const masterInst = await VerusBridgeMaster.deployed();
        const trans = tx.nobridgeUSDCSend;
        const storageInst = VerusBridgeStorage.deployed();
        const token = new web3.eth.Contract(TokenAbi.abi, "0xF0A1263056c30E221F0F851C36b767ffF2544f7F");
        const approveResult = await token.methods.increaseAllowance.sendTransaction(storageInst.address, "10000000", { from: accounts[0] });
        const test = await masterInst.methods.export(trans).sendTransaction({ from: accounts[0], value: "3000000000000000" }); //0.003 ETH fee

        assert.ok(true);
    });

    it("Should send 0.01 ETH to contract", async() => {
        const masterInst = await VerusBridgeMaster.deployed();
        const trans = tx.nobridgeETHSend;
        const test = await masterInst.methods.export(trans).sendTransaction({ from: accounts[0], value: "13000000000000000" }); //0.003 ETH fee + 0.01 ETH

        assert.ok(true);
    });

});