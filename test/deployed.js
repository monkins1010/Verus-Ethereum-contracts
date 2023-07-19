const VerusDelegator = artifacts.require("../contracts/Main/Delegator.sol");
const Token = artifacts.require("./VerusBridge/Token.sol");
const abi = require('web3-eth-abi');
const tx = require('../tx.json');
const TokenAbi = require('../build/contracts/ERC20.json');


contract("Verus Contracts deployed tests", async accounts => {

    it("Currencies Deployed", async() => {
        const TokenInst = await VerusDelegator.deployed();
        let tokens1 = await TokenInst.getTokenList.call(0,0);

        assert.equal(tokens1.length, 5);
    });

    // it("Should send 10 USDC to contract", async() => {
    //     const masterInst = await VerusBridgeMaster.deployed();
    //     const trans = tx.nobridgeUSDCSend;
    //     const storageInst = VerusBridgeStorage.deployed();
    //     const token = new web3.eth.Contract(TokenAbi.abi, "0xF0A1263056c30E221F0F851C36b767ffF2544f7F");
    //     const approveResult = await token.methods.increaseAllowance.sendTransaction(storageInst.address, "10000000", { from: accounts[0] });
    //     const test = await masterInst.methods.export(trans).sendTransaction({ from: accounts[0], value: "3000000000000000" }); //0.003 ETH fee

    //     assert.ok(true);
    // });

    // it("Should send 0.01 ETH to contract", async() => {
    //     const masterInst = await VerusBridgeMaster.deployed();
    //     const trans = tx.nobridgeETHSend;
    //     const test = await masterInst.methods.export(trans).sendTransaction({ from: accounts[0], value: "13000000000000000" }); //0.003 ETH fee + 0.01 ETH

    //     assert.ok(true);
    // });

});