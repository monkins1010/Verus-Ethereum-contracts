const VerusDelegator = artifacts.require("../contracts/Main/Delegator.sol");
const VerusSerializer = artifacts.require("../contracts/VerusBridge/VerusSerializer.sol");
const notaries = require('../migrations/setup.js')
const verusDelegatorAbi = require('../build/contracts/Delegator.json');
const verusSerializerAbi = require('../build/contracts/VerusSerializer.json');
const testNotarization = require('./submitnotarization.js')
const reservetransfer = require('./reservetransfer.ts')
const { toBase58Check } = require("verus-typescript-primitives");

contract("Verus Contracts deployed tests", async(accounts)  => {
    
    it("Currencies Deployed", async() => {
        const DelegatorInst = await VerusDelegator.deployed();
        let tokensList = await DelegatorInst.getTokenList.call(0,0);
        assert.equal(tokensList.length, 5);
    });

    it("Notaries Deployed", async() => {
        const DelegatorInst = await VerusDelegator.deployed();
        for (let i=0; i< notaries.TestVerusNotariserIDS.length; i++){

            let firstnotary = await DelegatorInst.notaries.call(i);
            assert.equal(firstnotary.toLowerCase(), notaries.TestVerusNotariserIDS[i].toLowerCase());

        }
        assert.ok(true);
    });

    it("Send 1 ETH to Contract", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        const contractAddress = DelegatorInst.address;
    
        // Get the contract balance before sending ETH
        const initialBalance = await web3.eth.getBalance(contractAddress);
    
        // Send 1 ETH to the contract
        const sendAmount = web3.utils.toWei("1", "ether");
        await web3.eth.sendTransaction({ from: accounts[0], to: contractAddress, value: sendAmount });
    
        // Get the contract balance after sending ETH
        const finalBalance = await web3.eth.getBalance(contractAddress);
    
        // Check if the contract balance increased by 1 ETH
        const expectedBalance = web3.utils.toBN(initialBalance).add(web3.utils.toBN(sendAmount));
        assert.equal(finalBalance.toString(), expectedBalance.toString(), "Contract balance is incorrect after sending ETH");
      });

      it("Send 1 ETH in Serialized ReserveTransfer to Contract", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        const contractAddress = DelegatorInst.address;

        const contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, contractAddress);
  
    
        // Send 1 ETH to the contract
        const sendAmount = web3.utils.toWei("1.003", "ether");
        const serializedTx = `0x${reservetransfer.prelaunchfundETH.toBuffer().toString('hex')}`;
        //console.log("reservetransfer transaction " + JSON.stringify(reservetransfer, null, 2))
        let reply
        try {
            reply = await contractInstance.methods.sendTransferDirect(serializedTx).send({ from: accounts[0], gas: 6000000, value: sendAmount }); 
            // Get the contract balance after sending ETH exportHeights
            const previousStartHeight = await DelegatorInst.exportHeights.call(0);
            let reserveimport = await DelegatorInst.getReadyExportsByRange.call(0, reply.blockNumber + 10);
        
          assert.equal(reply.blockNumber, reserveimport[0].endHeight, "Endheight should equal insertion height");
        } catch(e) {
            console.log(e.message)
            assert.ok(false);
        }

      });

      it("Send 2 ETH in ReserveTransfer to Contract", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        const contractAddress = DelegatorInst.address;
        const contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, contractAddress);
        // Send 1 ETH to the contract
        const sendAmount = web3.utils.toWei("2.003", "ether");

        const CReserveTransfer = {
            version: 1,
            currencyvalue: { currency: "0x67460C2f56774eD27EeB8685f29f6CEC0B090B00", amount: 200000000 }, // currency sending from ethereum
            flags: 1,
            feecurrencyid: "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d", // fee is vrsctest pre bridge launch, veth or others post.
            fees: 2000000,
            destination: { destinationtype: 2, destinationaddress: "0x9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD" }, // destination address currecny is going to
            destcurrencyid: "0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d",   // destination currency is vrsc on direct. bridge.veth on bounceback
            destsystemid: "0x0000000000000000000000000000000000000000",     // destination system not used 
            secondreserveid: "0x0000000000000000000000000000000000000000"    // used as return currency type on bounce back
          }
        let reply
        try {
            reply = await contractInstance.methods.sendTransfer(CReserveTransfer).send({ from: accounts[0], gas: 6000000, value: sendAmount }); 
        } catch(e) {
            console.log(e)
            assert.isTrue(false);
        }
        // Get the contract balance after sending ETH exportHeights
        const previousStartHeight = await DelegatorInst.exportHeights.call(0);
        let reserveimport = await DelegatorInst.getReadyExportsByRange.call(0, reply.blockNumber + 10);
        assert.isTrue(true);
      });

      it("Submitaccpeted notarization by Notary", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        const contractAddress = DelegatorInst.address;
        const contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, contractAddress);

        let reply;
        try {
            reply = await contractInstance.methods.setLatestData(testNotarization.serializednotarization, testNotarization.txid, testNotarization.voutnum,  testNotarization.abiencodedSigData).send({ from: accounts[0], gas: 6000000 });  
        } catch(e) {
            console.log(e)
            assert.isTrue(false);
        }
        // Get the contract balance after sending ETH exportHeights
        const notarization = await contractInstance.methods.bestForks(0).call();

         const NotarizationResult = {
           txid: notarization.substring(66, 130),
           n: parseInt(notarization.slice(202, 210), 16),
           hash: notarization.substring(2, 66),
        };
        assert.equal(`0x${NotarizationResult.txid}`, testNotarization.txid, "Txid in best forks does not equal notarization");
      });

      it("Test Serializer with bounceback", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        const prelaunchtx = `0x${reservetransfer.prelaunchfundETH.toBuffer().toString('hex')}`;
        const bounceback = `0x${reservetransfer.bounceback.toBuffer().toString('hex')}`;

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfer(bounceback).call();  
            console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }
        assert.equal(toBase58Check(Buffer.from(reply.secondreserveid.slice(2),'hex'), 102), reservetransfer.bounceback.second_reserve_id , "secondreserveid does not equal transaction");
      });

});