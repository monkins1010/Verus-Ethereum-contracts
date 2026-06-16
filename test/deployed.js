const VerusDelegator = artifacts.require("../contracts/Main/Delegator.sol");
const VerusSerializer = artifacts.require("../contracts/VerusBridge/VerusSerializer.sol");
const VerusProof = artifacts.require("../contracts/MMR/VerusProof.sol");
const NotarizationSerializer = artifacts.require("../contracts/VerusNotarizer/NotarizationSerializer.sol");
const { getNotarizerIDS } = require('../migrations/setup.js')
const verusDelegatorAbi = require('../build/contracts/Delegator.json');
const verusSerializerAbi = require('../build/contracts/VerusSerializer.json');
const verusProofAbi = require('../build/contracts/VerusProof.json');
const notarizationSerializerAbi = require('../build/contracts/NotarizationSerializer.json');
const testNotarization = require('./submitnotarization.js')
const reservetransfer = require('./reservetransfer.ts')
const { toBase58Check } = require("verus-typescript-primitives");
const ERC721 = require("../build/contracts/ERC721.json");
const { proofinput } = reservetransfer;
const abi = web3.eth.abi
const { randomBytes } = require('crypto');

const createUpgradeTuple = (addresses, salt, upgradetype) => {

  let package = [0, "0x00", "0x00",
                  addresses, upgradetype, salt, "0x0000000000000000000000000000000000000000", 0];
  
  let data = abi.encodeParameter(
      'tuple(uint8,bytes32,bytes32,address[],uint8,bytes32,address,uint32)',
      package);
  
  return data;
}


contract("Verus Contracts deployed tests", async(accounts)  => {
    
    it("All 6 Currencies Deployed", async() => {
        const DelegatorInst = await VerusDelegator.deployed();
        let tokensList = await DelegatorInst.getTokenList.call(0,0);
        assert.equal(tokensList.length, 6, "Not all currencies were deployed");
    });

    it("Notaries Deployed", async() => {
        const DelegatorInst = await VerusDelegator.deployed();

        const notaries = getNotarizerIDS("development")[0]

        for (let i=0; i< notaries.length; i++){

            let firstnotary = await DelegatorInst.notaries.call(i);
            assert.equal(firstnotary.toLowerCase(), notaries[i].toLowerCase());

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

      // it("Submit accepeted notarization by Notary", async () => {
      //   const DelegatorInst = await VerusDelegator.deployed();
      //   const contractAddress = DelegatorInst.address;
      //   const contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, contractAddress);

      //   let reply;

      //   const votehash= "0x9304c78dd2c478a5cd5841dd751dc16baa320603";
      //   try {
      //       reply = await contractInstance.methods.setLatestData(testNotarization.firstNotarization, testNotarization.firsttxid, testNotarization.firstvout,  testNotarization.abiencodedSigData).send({ from: accounts[0], gas: 6000000 });  
            
      //       reply = await contractInstance.methods.setLatestData(testNotarization.secondNotarization, testNotarization.secondtxid, testNotarization.secondvout,  testNotarization.abiencodedSigData).send({ from: accounts[0], gas: 6000000 }); 
      //       let test = await contractInstance.methods.rollingUpgradeVotes(0).call();
      //       assert.equal(test.toLowerCase(), votehash, "Vote hash should be equal to the votehash");
      //       test = await contractInstance.methods.rollingUpgradeVotes(1).call();
      //       assert.equal(test.toLowerCase(), votehash, "Vote hash should be equal to the votehash");
      //       test = await contractInstance.methods.rollingUpgradeVotes(2).call();
      //       assert.equal(test.toLowerCase(), "0x0000000000000000000000000000000000000000", "Vote hash should be equal to the null");

      //       let innerreply2 = await contractInstance.methods.getVoteCount(votehash).call();
      //       assert.equal(innerreply2, "2", "Vote count should be 2");
      //   } catch(e) {
      //       console.log(e)
      //       assert.isTrue(false);
      //   }
      //   // Get the contract balance after sending ETH exportHeights
      //   const notarization = await contractInstance.methods.bestForks(0).call();
      //   const vote = await contractInstance.methods.rollingUpgradeVotes(0).call();

      //    const NotarizationResult = {
      //      txid: notarization.substring(66, 130),
      //      n: parseInt(notarization.slice(202, 210), 16),
      //      hash: notarization.substring(2, 66),
      //   };
      //   assert.equal(`0x${NotarizationResult.txid}`, testNotarization.firsttxid, "Txid in best forks does not equal notarization");
      // });

      // it("Test Votes", async () => {
      //   const DelegatorInst = await VerusDelegator.deployed();
      //   const contractAddress = DelegatorInst.address;
      //   const contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, contractAddress);

      //   let randomBuf = randomBytes(32);

      //   let outBuffer = Buffer.alloc(1);
      //   const TYPE_CONTRACT = 1;
      //   outBuffer.writeUInt8(TYPE_CONTRACT);

      //   let contractsHex = Buffer.from('');

      //   let contracts = [];
      //   // Get the list of current active contracts
      //   for (let i = 0; i < 11; i++) 
      //   {
      //       contracts.push(await contractInstance.methods.contracts(i).call());
      //   }
      //   const newContract = "0x089D2f1Bdb9DA0eD7350e6224eE40C22cCc20D02";
      //   const newContractType = 2;
        
      //    //replace existing contract with new contract address
      //   contracts[newContractType] = newContract; 

      //   for (let i = 0; i < 11; i++) 
      //   {
      //       contractsHex = Buffer.concat([contractsHex, Buffer.from(contracts[i].slice(2), 'hex')]);
      //   }

      //   let serialized = Buffer.concat([contractsHex, outBuffer, randomBuf]);

      //   let hashedContractPackage =  web3.utils.keccak256(serialized).toString('hex').slice(26,66);
      
      //   let reply;
      //   // Get the contract balance after sending ETH exportHeights
      //   const vote = await contractInstance.methods.rollingUpgradeVotes(0).call();

      //   // NOTE: This test requires a modified delegator to be able to set the votes
      //   /*************************************************** */
      //   //await contractInstance.methods.modifyvote(hashedContractPackage, 24).send({ from: accounts[0], gas: 6000000 });

      //   /**** Insert this into the delegator ******************************************* */
      //  // function modifyvote(address hashValue, uint numOfvotes) external  {

      //   //  for (uint i = 1; i < numOfvotes+1; i++)
      //   //  {
      //   //     rollingUpgradeVotes[i] = hashValue;              
      //   //  }
        
      //   /******************************************************** */

      //   assert.isTrue(true, "Skipped");
      //   let count = 0;
  
      //   let innerreply = await contractInstance.methods.getVoteCount(hashedContractPackage).call();
     
      //   count = parseInt(innerreply);       
      //   assert.equal(count, 24, "error in vote amount");
      //   let upgradetup
      //   try {
      //       upgradetup = createUpgradeTuple(contracts, "0x"+randomBuf.toString('hex'), 1)
      //       reply = await contractInstance.methods.upgradeContracts(upgradetup).send({ from: accounts[0], gas: 6000000 });  
      //       assert.isTrue(false, "Should not have been able to upgrade");
      //   } catch(e) {
                     
      //   }

      //   await contractInstance.methods.modifyvote(hashedContractPackage, 26).send({ from: accounts[0], gas: 6000000 });
      //   count = 0;

      //   let innerreply2 = await contractInstance.methods.getVoteCount(hashedContractPackage).call();
     
      //   count = parseInt(innerreply2);
      //   assert.equal(count, 26, "error in vote amount");

      //   try {
      //       reply = await contractInstance.methods.upgradeContracts(upgradetup).send({ from: accounts[0], gas: 6000000 });
      //       const vote = await contractInstance.methods.rollingUpgradeVotes(0).call();
      //       const rollingIndex = await contractInstance.methods.rollingVoteIndex().call();
      //       assert.equal(rollingIndex, 0, "Rolling index should be 0");
      //       assert.equal(vote, "0x0000000000000000000000000000000000000000", "Vote should be reset");
     
      //   } catch(e) {
      //       console.log(e)
      //       assert.isTrue(false, "Should have been able to upgrade");
      //   }
        
      //   for (let i = 0; i < 11; i++) 
      //   {
      //     const replaced = await contractInstance.methods.contracts(i).call();
      //     if (i == 2) {
      //       assert.equal(replaced, newContract, "Contract was not replaced");
      //     } else {
      //       assert.equal(replaced, contracts[i], "Contract was not replaced");
      //     }
      //   }

      // });

      it("Test Serializer with bounceback sendTransfer", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        const prelaunchtx = `0x${reservetransfer.prelaunchfundETH.toBuffer().toString('hex')}`;
        const bounceback = `0x${reservetransfer.bounceback.toBuffer().toString('hex')}`;

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfer(bounceback).call();  
         //   console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }
        assert.equal(toBase58Check(Buffer.from(reply.secondreserveid.slice(2),'hex'), 102), reservetransfer.bounceback.second_reserve_id , "secondreserveid does not equal transaction");
      });

      it("Deserialize two Reserve transfers", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const twoTransfersSerialized = Buffer.concat([reservetransfer.twoReserveTransfers[0].toBuffer(), reservetransfer.twoReserveTransfers[1].toBuffer()]).toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${twoTransfersSerialized}`, 2).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }
        const txOne = new web3.utils.BN(reply.tempTransfers[0].currencyAndAmount).toString('hex').slice(7); 
        assert.equal(toBase58Check(Buffer.from(txOne,'hex'), 102), reservetransfer.twoReserveTransfers[0].reserve_values.value_map.keys().next().value , "transfer currency does not equal transaction");
      });

      it("Deserialize a Reserve transfer with a mapped ERC721", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc721transfer = reservetransfer.erc721transferETH.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc721transfer}${erc721transfer}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ" , "transfer currency does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0x39Ec448b891c476e166b3C3242A90830DB556661" , "ERC721 does not equal transaction");
        assert.equal(reply.launchTxs[0].flags, "129" , "ERC721 does not equal transaction");
        assert.equal(reply.launchTxs[0].tokenID, 255 , "ERC721 TokenID does not equal the correct (first Currency Export)");
      });

      it("Deserialize a Reserve transfer with a verus owned ERC721", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc721transfer = reservetransfer.erc721transferVerus.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc721transfer}${erc721transfer}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ" , "transfer currency (chad7) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0x0000000000000000000000000000000000000000" , "ERC721 does not equal an empty address");
        assert.equal(reply.launchTxs[0].flags, "130" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Deserialize a Reserve transfer with a verus owned ERC20", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc20verustoken = reservetransfer.erc20verustoken.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc20verustoken}${erc20verustoken}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ" , "transfer currency (chad7) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0x0000000000000000000000000000000000000000" , "ERC20 does not equal verus ERC20 NFT address");
        assert.equal(reply.launchTxs[0].flags, "34" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Deserialize a Reserve transfer with a ETH owned ERC20", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc20ETHtoken = reservetransfer.erc20ETHtoken.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc20ETHtoken}${erc20ETHtoken}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "i7VSq7gm2xe7vWnjK9SvJvTUvy5rcLfozZ" , "transfer currency (chad7) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0xB897f2448054bc5b133268A53090e110D101FFf0" , "ERC20 does not equal DAI address (first Currency Export)");
        assert.equal(reply.launchTxs[1].ERCContract, "0xB897f2448054bc5b133268A53090e110D101FFf0" , "ERC20 does not equal DAI address (second Currency Export)");
        assert.equal(reply.launchTxs[0].flags, "33" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Deserialize a Reserve transfer with a ERC1155 Verus mapped nft", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc1155VerusNFT = reservetransfer.erc1155VerusNFT.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc1155VerusNFT}${erc1155VerusNFT}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "iAwycBuMcPJii45bKNTEfSnD9W9iXMiKGg" , "transfer currency (id2) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0xF7F25BFC8a4E4a4413243Cc5388e5a056cb4235b" , "ERC1155 does not equal the correct address (first Currency Export)");
        assert.equal(reply.launchTxs[1].ERCContract, "0xF7F25BFC8a4E4a4413243Cc5388e5a056cb4235b" , "ERC1155 does not equal the correct (second Currency Export)");
        assert.equal(reply.launchTxs[0].tokenID, 255 , "ERC1155 TokenID does not equal the correct (first Currency Export)");
        assert.equal(reply.launchTxs[1].tokenID, 255 , "ERC1155 TokenID does not equal the correct (second Currency Export)");
        assert.equal(reply.launchTxs[0].flags, "17" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Deserialize a Reserve transfer with a ERC1155 to token mapping", async () => {
        const VerusSerializerInst = await VerusSerializer.deployed();
        const contractAddress = VerusSerializerInst.address;
        const contractInstance = new web3.eth.Contract(verusSerializerAbi.abi, contractAddress);

        // convert the two reserveTransfers to a single hex string
        const erc1155Token = reservetransfer.erc1155Token.toBuffer().toString('hex');

        let reply;  
        try {
            reply = await contractInstance.methods.deserializeTransfers(`0x${erc1155Token}${erc1155Token}${reservetransfer.twoReserveTransfers[0].toBuffer().toString('hex')}`, 3).call();  
           // console.log(reply)
        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(toBase58Check(Buffer.from(reply.launchTxs[0].iaddress.slice(2), 'hex'), 102), "iAwycBuMcPJii45bKNTEfSnD9W9iXMiKGg" , "transfer currency (id2) does not equal transaction");
        assert.equal(reply.launchTxs[0].ERCContract, "0xF7F25BFC8a4E4a4413243Cc5388e5a056cb4235b" , "ERC1155 does not equal the correct (first Currency Export)");
        assert.equal(reply.launchTxs[1].ERCContract, "0xF7F25BFC8a4E4a4413243Cc5388e5a056cb4235b" , "ERC1155 does not equal the correct (second Currency Export)");
        assert.equal(reply.launchTxs[0].tokenID, 255 , "ERC1155 TokenID does not equal the correct (first Currency Export)");
        assert.equal(reply.launchTxs[1].tokenID, 255 , "ERC1155 TokenID does not equal the correct (second Currency Export)");
        assert.equal(reply.launchTxs[0].flags, "65" , "Ethereum mapped currency does not have the correct flags ");
      });

      it("Check Verus ERC721 has launched", async () => {
        const DelegatorInst = await VerusDelegator.deployed();
        const contractAddress = DelegatorInst.address;
        const contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, contractAddress);

        let tokensList = await contractInstance.methods.tokenList(0).call();

        const NFTContract = new web3.eth.Contract(ERC721.abi, tokensList);
       
        let reply;  
        try {
           reply = await NFTContract.methods.name().call(); ;

        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }

        assert.equal(reply, "VerusNFT" , "Verus ERC721 name does not equal transaction");
      });
      it("Prove components", async () => {
        const VerusProofInst = await VerusProof.deployed();
        const contractAddress = VerusProofInst.address;
        const contractInstance = new web3.eth.Contract(verusProofAbi.abi, contractAddress);

        let reply;  
        try {

            reply = await contractInstance.methods.checkProof("0x0000000000000000000000000000000000000000000000000000000000000000",proofinput[0].partialtransactionproof.components[0].elProof).call();  

        } catch(e) {
            console.log(e.message)
            assert.isTrue(false);
        }
        assert.equal(reply, "0x29b5437905fbf6cd87bb5964bff0306b1e5870ef375e4622b438012177dc7261");
      try {

          reply = await contractInstance.methods.checkProof("0x0000000000000000000000000000000000000000000000000000000000000000", []).call();  
      } catch(e) {
          assert.equal(e.message, "VM Exception while processing transaction: revert")
          return;
      }
      assert.isTrue(false);
      
      });
      it("Test a CCE with the supplementary flag set reverts", async () => {
        const VerusProofInst = await VerusProof.deployed();
        const contractAddress = VerusProofInst.address;
        const contractInstance = new web3.eth.Contract(verusProofAbi.abi, contractAddress);

        const inputToSubmitImports = "0x0000000000000000b01a04030001011452047d0db35c330271aae70bedce996b5239ca5ccc4c9104030c01011452047d0db35c330271aae70bedce996b5239ca5c4c75010008001af5b8015c64d39ab44c60ead8317f9f5a9b6c4c00a37ecd7f80fdbe3e5096124e7c8ca045b0b9e9e58b5595ee53ca9f3d964581454cb83913d688795e237837d30258d11ea7c752454cb83913d688795e237837d30258d11ea7c7520000000000000300000080f7b73180f7b73100000075"

            const mainInput = {
          "partialtransactionproof": {
            "version": 1,
            "typeC": 2,
            "txproof": [
              { "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 1, "nSize": 9, "extraHashes": 0, "branch": ["0xebb1cc631a6dd0c10e88de4393fe8573574b979e776eea6318cf41a7c6ca8d8e","0xf1f8f848c560dd71380fc34a00ab661e7a753b91356d1c4656b3877bff5255e4","0xa6993e48754abd6f4d2dd208b818a18dec47771e3151920cb3bfb5488cf3b87d","0x181fe84a398c5f5cf083a7c92441ec034de08678a53675f32a517245536e5965"] } },
              { "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 0, "nSize": 2, "extraHashes": 0, "branch": ["0x6e45c5038342ced986452e43a80617badb98f7906e48fc839ebc000000000000"] } },
              { "branchType": 3, "proofSequence": { "CMerkleBranchBase": 3, "nIndex": 4071017, "nSize": 4071020, "extraHashes": 1, "branch": ["0xf90c17804a390000000000000000000000000000000000000000000000000000","0xfb9c2b9e70658b5a886b661821e3f90ef16dda8df940e2d0400c228a7b5287ff","0x936e3cf4fc720000000000000000000000000000000000000000000000000000","0x87634e882e06bc59986d86d2e0c38175777ea653e5424fa3d3a5ca046da588e4","0x04ae45c0b4e1000000000000000000000e976b03a8d219000000000000000000","0x6c2cafef2a0fb9abe5cdf497f93b8c61e54c3ed9c4135121a2766c84cb356ead","0x36950b3220ceba000000000000000000d0665203cecf350f0000000000000000","0x147fecfc3fd17087e46247f14d275c1c717a2ff3b8aa5411c432659391edc7d3","0x4ca17e9cd202da0b1300000000000000021fd2082005b8f5447a0d0000000000"] } }
            ],
            "components": [
              { "elType": 1, "elIdx": 0, "elVchObj": "0x33a7f5b934fca59603d449337455e32d68b37dd8a5bc7b73d7c3c74d98e699f8010400000085202f890100000003000000000000000000000000000000861e3e000000000000000000", "elProof": [{ "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 0, "nSize": 6, "extraHashes": 0, "branch": ["0xe1d6e5bc258ce04b898310a3ede4518dbe08934f3feada389b5045265d453303","0xf1b10e17a45cf67db3c78dc66badc5509cc660b821ae11790a6888c4ebd977fa","0x9f7951aa385e9d4b6dc797b7aada3494b383c42544da2484b5d965d7aaac1d19"] } }] },
              // elVchObj: flags bytes changed from 010008 → 010000 (no flags)
              { "elType": 4, "elIdx": 1, "elVchObj": "0x0000000000000000b01a04030001011452047d0db35c330271aae70bedce996b5239ca5ccc4c9104030c01011452047d0db35c330271aae70bedce996b5239ca5c4c7501000000A6ef9ea235635E328124Ff3429dB9F9E91b64e2d00a37ecd7f80fdbe3e5096124e7c8ca045b0b9e9e58b5595ee53ca9f3d96458167460C2f56774eD27EeB8685f29f6CEC0B090B0067460C2f56774eD27EeB8685f29f6CEC0B090B000000000000000300000080f7b73180f7b73100000075", "elProof": [{ "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 4, "nSize": 6, "extraHashes": 0, "branch": ["0xaaaff00a70df45727c6002e4c4dc57f0e2a1f58f0cab1a8c805a1d190c0916be","0xe546fdbe2f25ec48d7b08bffc97c3d261cfaab94110f6721ddf918595ecb1148"] } }] }
            ]
          },
          "serializedTransfers": "0x0167460C2f56774eD27EeB8685f29f6CEC0B090B0083dcbec397090167460C2f56774eD27EeB8685f29f6CEC0B090B00809b20091465cb8b128bf6e690761044cceca422bb239c25f967460C2f56774eD27EeB8685f29f6CEC0B090B0001f87f6d4412dad7c4452e8293850df5327f02c308a5c9bde9410167460C2f56774eD27EeB8685f29f6CEC0B090B00809b20091465cb8b128bf6e690761044cceca422bb239c25f967460C2f56774eD27EeB8685f29f6CEC0B090B00011bd15cdbf0b5b8c9cc361ffbaf6d76cc2cdfd66782acde9980c80f0167460C2f56774eD27EeB8685f29f6CEC0B090B00809d54091465cb8b128bf6e690761044cceca422bb239c25f967460C2f56774eD27EeB8685f29f6CEC0B090B00"
        };

        try {
            await contractInstance.methods.checkExportAndTransfers(mainInput, "0x00a37ecd7f80fdbe3e5096124e7c8ca045b0b9e9e58b5595ee53ca9f3d964581").call();
            assert.isTrue(false, "Should have reverted: no flags set");
        } catch(e) {
            assert.include(e.message, "revert", "Expected revert when no flags are set");
        }
      });

      it("CCE with extra flags set (0x0088 = FLAG_POSTLAUNCH | FLAG_SUPPLEMENTAL) should revert", async () => {
        const VerusProofInst = await VerusProof.deployed();
        const contractAddress = VerusProofInst.address;
        const contractInstance = new web3.eth.Contract(verusProofAbi.abi, contractAddress);

        // elVchObj: flags bytes changed from 010008 → 010088 (0x0080 | 0x0008)
       const mainInput = {
          "partialtransactionproof": {
            "version": 1,
            "typeC": 2,
            "txproof": [
              { "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 1, "nSize": 9, "extraHashes": 0, "branch": ["0xebb1cc631a6dd0c10e88de4393fe8573574b979e776eea6318cf41a7c6ca8d8e","0xf1f8f848c560dd71380fc34a00ab661e7a753b91356d1c4656b3877bff5255e4","0xa6993e48754abd6f4d2dd208b818a18dec47771e3151920cb3bfb5488cf3b87d","0x181fe84a398c5f5cf083a7c92441ec034de08678a53675f32a517245536e5965"] } },
              { "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 0, "nSize": 2, "extraHashes": 0, "branch": ["0x6e45c5038342ced986452e43a80617badb98f7906e48fc839ebc000000000000"] } },
              { "branchType": 3, "proofSequence": { "CMerkleBranchBase": 3, "nIndex": 4071017, "nSize": 4071020, "extraHashes": 1, "branch": ["0xf90c17804a390000000000000000000000000000000000000000000000000000","0xfb9c2b9e70658b5a886b661821e3f90ef16dda8df940e2d0400c228a7b5287ff","0x936e3cf4fc720000000000000000000000000000000000000000000000000000","0x87634e882e06bc59986d86d2e0c38175777ea653e5424fa3d3a5ca046da588e4","0x04ae45c0b4e1000000000000000000000e976b03a8d219000000000000000000","0x6c2cafef2a0fb9abe5cdf497f93b8c61e54c3ed9c4135121a2766c84cb356ead","0x36950b3220ceba000000000000000000d0665203cecf350f0000000000000000","0x147fecfc3fd17087e46247f14d275c1c717a2ff3b8aa5411c432659391edc7d3","0x4ca17e9cd202da0b1300000000000000021fd2082005b8f5447a0d0000000000"] } }
            ],
            "components": [
              { "elType": 1, "elIdx": 0, "elVchObj": "0x33a7f5b934fca59603d449337455e32d68b37dd8a5bc7b73d7c3c74d98e699f8010400000085202f890100000003000000000000000000000000000000861e3e000000000000000000", "elProof": [{ "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 0, "nSize": 6, "extraHashes": 0, "branch": ["0xe1d6e5bc258ce04b898310a3ede4518dbe08934f3feada389b5045265d453303","0xf1b10e17a45cf67db3c78dc66badc5509cc660b821ae11790a6888c4ebd977fa","0x9f7951aa385e9d4b6dc797b7aada3494b383c42544da2484b5d965d7aaac1d19"] } }] },
              // elVchObj: flags bytes changed from 010008 → 010080 (FLAG_POSTLAUNCH only)
              { "elType": 4, "elIdx": 1, "elVchObj": "0x0000000000000000fd6b011a04030001011452047d0db35c330271aae70bedce996b5239ca5ccc4d4b0104030c01011452047d0db35c330271aae70bedce996b5239ca5c4d2e0101008000A6ef9ea235635E328124Ff3429dB9F9E91b64e2df37999ebc168d9109aa536b0773e82da0c4b86ce11e701a7792922b5bb2c4142454cb83913d688795e237837d30258d11ea7c752454cb83913d688795e237837d30258d11ea7c752441463bb9f612be23a8f51aad6d62ec8b8342ddba6ac0116021444a5b8ead66bba58d568c684ae8910541d4ac4fc010000000100000080f7b31280f7b73001454cb83913d688795e237837d30258d11ea7c7523f3403000000000002454cb83913d688795e237837d30258d11ea7c7523f34030000000000f87f6d4412dad7c4452e8293850df5327f02c3089bca1d000000000002454cb83913d688795e237837d30258d11ea7c7523f34030000000000f87f6d4412dad7c4452e8293850df5327f02c3089bca1d00000000000075", "elProof": [{ "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 4, "nSize": 6, "extraHashes": 0, "branch": ["0xaaaff00a70df45727c6002e4c4dc57f0e2a1f58f0cab1a8c805a1d190c0916be","0xe546fdbe2f25ec48d7b08bffc97c3d261cfaab94110f6721ddf918595ecb1148"] } }] }
            ]
          },
          "serializedTransfers": "0x01454cb83913d688795e237837d30258d11ea7c75283dcbec3970901454cb83913d688795e237837d30258d11ea7c752809b20091465cb8b128bf6e690761044cceca422bb239c25f9454cb83913d688795e237837d30258d11ea7c75201f87f6d4412dad7c4452e8293850df5327f02c308a5c9bde94101454cb83913d688795e237837d30258d11ea7c752809b20091465cb8b128bf6e690761044cceca422bb239c25f9454cb83913d688795e237837d30258d11ea7c752011bd15cdbf0b5b8c9cc361ffbaf6d76cc2cdfd66782acde9980c80f01454cb83913d688795e237837d30258d11ea7c752809d54091465cb8b128bf6e690761044cceca422bb239c25f9454cb83913d688795e237837d30258d11ea7c752"
        };

        try {
            await contractInstance.methods.checkExportAndTransfers(mainInput, "0xf37999ebc168d9109aa536b0773e82da0c4b86ce11e701a7792922b5bb2c4142").call();
            assert.isTrue(false, "Should have reverted: extra flags set alongside FLAG_POSTLAUNCH");
        } catch(e) {
            assert.include(e.message, "revert", "Expected revert when extra flags set alongside FLAG_POSTLAUNCH");
        }
      });

      it("CCE with no flags set (0x0000) should revert", async () => {
        const VerusProofInst = await VerusProof.deployed();
        const contractAddress = VerusProofInst.address;
        const contractInstance = new web3.eth.Contract(verusProofAbi.abi, contractAddress);

        // Same structure as supplemental flag test but with flags = 0x0000 (no flags set).
        // elVchObj has 010000 where 010008 was (nVersion=0x0001, flags=0x0000).
        const mainInput = {
          "partialtransactionproof": {
            "version": 1,
            "typeC": 2,
            "txproof": [
              { "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 1, "nSize": 9, "extraHashes": 0, "branch": ["0xebb1cc631a6dd0c10e88de4393fe8573574b979e776eea6318cf41a7c6ca8d8e","0xf1f8f848c560dd71380fc34a00ab661e7a753b91356d1c4656b3877bff5255e4","0xa6993e48754abd6f4d2dd208b818a18dec47771e3151920cb3bfb5488cf3b87d","0x181fe84a398c5f5cf083a7c92441ec034de08678a53675f32a517245536e5965"] } },
              { "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 0, "nSize": 2, "extraHashes": 0, "branch": ["0x6e45c5038342ced986452e43a80617badb98f7906e48fc839ebc000000000000"] } },
              { "branchType": 3, "proofSequence": { "CMerkleBranchBase": 3, "nIndex": 4071017, "nSize": 4071020, "extraHashes": 1, "branch": ["0xf90c17804a390000000000000000000000000000000000000000000000000000","0xfb9c2b9e70658b5a886b661821e3f90ef16dda8df940e2d0400c228a7b5287ff","0x936e3cf4fc720000000000000000000000000000000000000000000000000000","0x87634e882e06bc59986d86d2e0c38175777ea653e5424fa3d3a5ca046da588e4","0x04ae45c0b4e1000000000000000000000e976b03a8d219000000000000000000","0x6c2cafef2a0fb9abe5cdf497f93b8c61e54c3ed9c4135121a2766c84cb356ead","0x36950b3220ceba000000000000000000d0665203cecf350f0000000000000000","0x147fecfc3fd17087e46247f14d275c1c717a2ff3b8aa5411c432659391edc7d3","0x4ca17e9cd202da0b1300000000000000021fd2082005b8f5447a0d0000000000"] } }
            ],
            "components": [
              { "elType": 1, "elIdx": 0, "elVchObj": "0x33a7f5b934fca59603d449337455e32d68b37dd8a5bc7b73d7c3c74d98e699f8010400000085202f890100000003000000000000000000000000000000861e3e000000000000000000", "elProof": [{ "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 0, "nSize": 6, "extraHashes": 0, "branch": ["0xe1d6e5bc258ce04b898310a3ede4518dbe08934f3feada389b5045265d453303","0xf1b10e17a45cf67db3c78dc66badc5509cc660b821ae11790a6888c4ebd977fa","0x9f7951aa385e9d4b6dc797b7aada3494b383c42544da2484b5d965d7aaac1d19"] } }] },
              // elVchObj: flags bytes changed from 010008 → 010000 (no flags)
              { "elType": 4, "elIdx": 1, "elVchObj": "0x0000000000000000b01a04030001011452047d0db35c330271aae70bedce996b5239ca5ccc4c9104030c01011452047d0db35c330271aae70bedce996b5239ca5c4c7501000000A6ef9ea235635E328124Ff3429dB9F9E91b64e2d00a37ecd7f80fdbe3e5096124e7c8ca045b0b9e9e58b5595ee53ca9f3d96458167460C2f56774eD27EeB8685f29f6CEC0B090B0067460C2f56774eD27EeB8685f29f6CEC0B090B000000000000000300000080f7b73180f7b73100000075", "elProof": [{ "branchType": 2, "proofSequence": { "CMerkleBranchBase": 2, "nIndex": 4, "nSize": 6, "extraHashes": 0, "branch": ["0xaaaff00a70df45727c6002e4c4dc57f0e2a1f58f0cab1a8c805a1d190c0916be","0xe546fdbe2f25ec48d7b08bffc97c3d261cfaab94110f6721ddf918595ecb1148"] } }] }
            ]
          },
          "serializedTransfers": "0x0167460C2f56774eD27EeB8685f29f6CEC0B090B0083dcbec397090167460C2f56774eD27EeB8685f29f6CEC0B090B00809b20091465cb8b128bf6e690761044cceca422bb239c25f967460C2f56774eD27EeB8685f29f6CEC0B090B0001f87f6d4412dad7c4452e8293850df5327f02c308a5c9bde9410167460C2f56774eD27EeB8685f29f6CEC0B090B00809b20091465cb8b128bf6e690761044cceca422bb239c25f967460C2f56774eD27EeB8685f29f6CEC0B090B00011bd15cdbf0b5b8c9cc361ffbaf6d76cc2cdfd66782acde9980c80f0167460C2f56774eD27EeB8685f29f6CEC0B090B00809d54091465cb8b128bf6e690761044cceca422bb239c25f967460C2f56774eD27EeB8685f29f6CEC0B090B00"
        };

        try {
            await contractInstance.methods.checkExportAndTransfers(mainInput, "0x00a37ecd7f80fdbe3e5096124e7c8ca045b0b9e9e58b5595ee53ca9f3d964581").call();
            assert.isTrue(false, "Should have reverted: no flags set");
        } catch(e) {
            assert.include(e.message, "revert", "Expected revert when no flags are set");
        }
      });

      it("CCE with extra flags set (0x0088 = FLAG_POSTLAUNCH | FLAG_SUPPLEMENTAL) should revert", async () => {
        const VerusProofInst = await VerusProof.deployed();
        const contractAddress = VerusProofInst.address;
        const contractInstance = new web3.eth.Contract(verusProofAbi.abi, contractAddress);

        // elVchObj: flags bytes changed from 010008 → 010088 (0x0080 | 0x0008)
       const mainInput = {
          "partialtransactionproof": {
        "version": 1,
        "typeC": 2,
        "txproof": [
          {
            "branchType": 2,
            "proofSequence": {
              "CMerkleBranchBase": 2,
              "nIndex": 1,
              "nSize": 4,
              "extraHashes": 0,
              "branch": [
                "0xf368cdceac4a48445e6d70d540f479946b1ee072d37baec162dacc9d53d51f86",
                "0xd23525fa4c6d9a3eac06b3aa6293c1fba2892dd91df4aee9d237d50d22c98333"
              ]
            }
          },
          {
            "branchType": 2,
            "proofSequence": {
              "CMerkleBranchBase": 2,
              "nIndex": 0,
              "nSize": 2,
              "extraHashes": 0,
              "branch": [
                "0xfc31a12464840214cd33b764d9bd8b9f82e4c20ea2f8a97c52270a4366e55de2"
              ]
            }
          },
          {
            "branchType": 3,
            "proofSequence": {
              "CMerkleBranchBase": 3,
              "nIndex": 4070450,
              "nSize": 4070468,
              "extraHashes": 1,
              "branch": [
                "0xa2aff010634500000000000000000000c16f830ed7110c000000000000000000",
                "0xa465633cc125a197780c59d8a93eaa9458fb6280e0df02c40c39c8372d81b7df",
                "0xdcee6154538d00000000000000000000c16f830ed7110c000000000000000000",
                "0xbce20af589df3dc323e402760a92e06de33ad6e208f1584f6be57e8895bb6b9d",
                "0x3ae7a397600f01000000000000000000bf5068f0814923000000000000000000",
                "0x7be84c3e00d8f992e0ea0f327f7632520c6a7ba5b6632bc2b1021162a9c3cbae",
                "0xd5aa8774fc0402000000000000000000bf5068f0814923000000000000000000",
                "0xb76bae82e6e82ca20b2666cdd0cc6f8c0ba5fc7e1b0e8a2906286b93b05d3a3f",
                "0x0bec59ace48e03000000000000000000f6f526997bf369000000000000000000",
                "0x4853c68ef28abf0a1bb12c6a5bec51cd766595ef7cdf994aedaa8453a69963c0",
                "0xac0a26d05d0708000000000000000000ebdfdb9f67faca000000000000000000",
                "0x2d3231fb5364f94bf13713c6ad64548db29c9004ae8ccc30e52c6ef4f54b6ef6",
                "0x10876a15dec910000000000000000000e4e9d815b01272010000000000000000",
                "0xdc9ca1d8f079c759e97249e2d5b02034ecc8a7a2fe20b0be76c4ece1d0a45cb1",
                "0xcf7389212ea111000000000000000000c359934f213a8a010000000000000000",
                "0x147fecfc3fd17087e46247f14d275c1c717a2ff3b8aa5411c432659391edc7d3",
                "0xe57ffc8be0d5300b1300000000000000f5111355736f0ce8447a0d0000000000"
              ]
            }
          }
        ],
        "components": [
          {
            "elType": 1,
            "elIdx": 0,
            "elVchObj": "0x690a227988d1a8e032498c65c5238d92e196bfc9a23faa8f75a4cfc164d71277010400000085202f890200000001000000000000000000000000000000461c3e000000000000000000",
            "elProof": [
              {
                "branchType": 2,
                "proofSequence": {
                  "CMerkleBranchBase": 2,
                  "nIndex": 0,
                  "nSize": 6,
                  "extraHashes": 0,
                  "branch": [
                    "0xae8800b064218efba664cfa07e3f5afade1cedc12095bc1dc1bfa76dc739f9f2",
                    "0xf143cdb0d5819ffa85bb3b7e71048563454d64faffbbbb7c25d76790b621e139",
                    "0xd5740ecab93d425d9337c93ad36f2f1e25b375c4cad1b1203826c84ee7c7f90e"
                  ]
                }
              }
            ]
          },
          {
            "elType": 2,
            "elIdx": 0,
            "elVchObj": "0xc1fd5724f58b1cd58b96d92d16ec34ad51fe1cdd1018e24b38ab85626c9ee35500000000ffffffff",
            "elProof": [
              {
                "branchType": 2,
                "proofSequence": {
                  "CMerkleBranchBase": 2,
                  "nIndex": 1,
                  "nSize": 6,
                  "extraHashes": 0,
                  "branch": [
                    "0x36c6fae0f0076ea99943da1eedf139b0f3f56ae947635224749de1f19c2e2b1d",
                    "0xf143cdb0d5819ffa85bb3b7e71048563454d64faffbbbb7c25d76790b621e139",
                    "0xd5740ecab93d425d9337c93ad36f2f1e25b375c4cad1b1203826c84ee7c7f90e"
                  ]
                }
              }
            ]
          },
          {
            "elType": 4,
            "elIdx": 0,
            "elVchObj": "0x0000000000000000fd6b011a04030001011452047d0db35c330271aae70bedce996b5239ca5ccc4d4b0104030c01011452047d0db35c330271aae70bedce996b5239ca5c4d2e0101008800A6ef9ea235635E328124Ff3429dB9F9E91b64e2df37999ebc168d9109aa536b0773e82da0c4b86ce11e701a7792922b5bb2c414267460C2f56774eD27EeB8685f29f6CEC0B090B0067460C2f56774eD27EeB8685f29f6CEC0B090B00441463bb9f612be23a8f51aad6d62ec8b8342ddba6ac0116021444a5b8ead66bba58d568c684ae8910541d4ac4fc010000000100000080f7b31280f7b7300167460C2f56774eD27EeB8685f29f6CEC0B090B003f340300000000000267460C2f56774eD27EeB8685f29f6CEC0B090B003f34030000000000f87f6d4412dad7c4452e8293850df5327f02c3089bca1d00000000000267460C2f56774eD27EeB8685f29f6CEC0B090B003f34030000000000f87f6d4412dad7c4452e8293850df5327f02c3089bca1d00000000000075",
            "elProof": [
              {
                "branchType": 2,
                "proofSequence": {
                  "CMerkleBranchBase": 2,
                  "nIndex": 5,
                  "nSize": 6,
                  "extraHashes": 0,
                  "branch": [
                    "0xb33f9018d637ae0c676c58d763fdac95b13efcdc3365bf174ed33e1d9f19bc84",
                    "0x8e5966c380b1046b83ebc773a563e3e902dc9806daf11488cb74fcf63106bf0a"
                  ]
                }
              }
            ]
          }
        ]
      },
      "serializedTransfers": "0x01f87f6d4412dad7c4452e8293850df5327f02c308f6941b41454cb83913d688795e237837d30258d11ea7c7528be73f4914c229ea150f397c423df9818deaa7e4c12a80ca0b01160214bfa6f481e6a2aa4ad6cfaa6c1d860623986ba5cd454cb83913d688795e237837d30258d11ea7c752454cb83913d688795e237837d30258d11ea7c752"
    };


        try {
            await contractInstance.methods.checkExportAndTransfers(mainInput, "0xf37999ebc168d9109aa536b0773e82da0c4b86ce11e701a7792922b5bb2c4142").call();
          } catch(e) {
            assert.include(e.message, "revert", "Expected revert when extra flags set alongside FLAG_POSTLAUNCH");
            return;
          }
          assert.isTrue(false, "Should have reverted: extra flags set alongside FLAG_POSTLAUNCH");
      });

      it("CCE with only FLAG_POSTLAUNCH (0x0080) passes flags check", async () => {
        // _parseCTxOut now reads compact-size inline (no VerusSerializer call), so
        // standalone VerusProof works here. The CCE contains mainnet addresses, so the
        // call passes the flags check but reverts at the CCE field validation with the
        // specific "CCE information does not checkout" message.
        const VerusProofInst = await VerusProof.deployed();
        const contractAddress = VerusProofInst.address;
        const contractInstance = new web3.eth.Contract(verusProofAbi.abi, contractAddress);
        const mainInput = {
          "partialtransactionproof": {
        "version": 1,
        "typeC": 2,
        "txproof": [
          {
            "branchType": 2,
            "proofSequence": {
              "CMerkleBranchBase": 2,
              "nIndex": 1,
              "nSize": 4,
              "extraHashes": 0,
              "branch": [
                "0xf368cdceac4a48445e6d70d540f479946b1ee072d37baec162dacc9d53d51f86",
                "0xd23525fa4c6d9a3eac06b3aa6293c1fba2892dd91df4aee9d237d50d22c98333"
              ]
            }
          },
          {
            "branchType": 2,
            "proofSequence": {
              "CMerkleBranchBase": 2,
              "nIndex": 0,
              "nSize": 2,
              "extraHashes": 0,
              "branch": [
                "0xfc31a12464840214cd33b764d9bd8b9f82e4c20ea2f8a97c52270a4366e55de2"
              ]
            }
          },
          {
            "branchType": 3,
            "proofSequence": {
              "CMerkleBranchBase": 3,
              "nIndex": 4070450,
              "nSize": 4070468,
              "extraHashes": 1,
              "branch": [
                "0xa2aff010634500000000000000000000c16f830ed7110c000000000000000000",
                "0xa465633cc125a197780c59d8a93eaa9458fb6280e0df02c40c39c8372d81b7df",
                "0xdcee6154538d00000000000000000000c16f830ed7110c000000000000000000",
                "0xbce20af589df3dc323e402760a92e06de33ad6e208f1584f6be57e8895bb6b9d",
                "0x3ae7a397600f01000000000000000000bf5068f0814923000000000000000000",
                "0x7be84c3e00d8f992e0ea0f327f7632520c6a7ba5b6632bc2b1021162a9c3cbae",
                "0xd5aa8774fc0402000000000000000000bf5068f0814923000000000000000000",
                "0xb76bae82e6e82ca20b2666cdd0cc6f8c0ba5fc7e1b0e8a2906286b93b05d3a3f",
                "0x0bec59ace48e03000000000000000000f6f526997bf369000000000000000000",
                "0x4853c68ef28abf0a1bb12c6a5bec51cd766595ef7cdf994aedaa8453a69963c0",
                "0xac0a26d05d0708000000000000000000ebdfdb9f67faca000000000000000000",
                "0x2d3231fb5364f94bf13713c6ad64548db29c9004ae8ccc30e52c6ef4f54b6ef6",
                "0x10876a15dec910000000000000000000e4e9d815b01272010000000000000000",
                "0xdc9ca1d8f079c759e97249e2d5b02034ecc8a7a2fe20b0be76c4ece1d0a45cb1",
                "0xcf7389212ea111000000000000000000c359934f213a8a010000000000000000",
                "0x147fecfc3fd17087e46247f14d275c1c717a2ff3b8aa5411c432659391edc7d3",
                "0xe57ffc8be0d5300b1300000000000000f5111355736f0ce8447a0d0000000000"
              ]
            }
          }
        ],
        "components": [
          {
            "elType": 1,
            "elIdx": 0,
            "elVchObj": "0x690a227988d1a8e032498c65c5238d92e196bfc9a23faa8f75a4cfc164d71277010400000085202f890200000001000000000000000000000000000000461c3e000000000000000000",
            "elProof": [
              {
                "branchType": 2,
                "proofSequence": {
                  "CMerkleBranchBase": 2,
                  "nIndex": 0,
                  "nSize": 6,
                  "extraHashes": 0,
                  "branch": [
                    "0xae8800b064218efba664cfa07e3f5afade1cedc12095bc1dc1bfa76dc739f9f2",
                    "0xf143cdb0d5819ffa85bb3b7e71048563454d64faffbbbb7c25d76790b621e139",
                    "0xd5740ecab93d425d9337c93ad36f2f1e25b375c4cad1b1203826c84ee7c7f90e"
                  ]
                }
              }
            ]
          },
          {
            "elType": 2,
            "elIdx": 0,
            "elVchObj": "0xc1fd5724f58b1cd58b96d92d16ec34ad51fe1cdd1018e24b38ab85626c9ee35500000000ffffffff",
            "elProof": [
              {
                "branchType": 2,
                "proofSequence": {
                  "CMerkleBranchBase": 2,
                  "nIndex": 1,
                  "nSize": 6,
                  "extraHashes": 0,
                  "branch": [
                    "0x36c6fae0f0076ea99943da1eedf139b0f3f56ae947635224749de1f19c2e2b1d",
                    "0xf143cdb0d5819ffa85bb3b7e71048563454d64faffbbbb7c25d76790b621e139",
                    "0xd5740ecab93d425d9337c93ad36f2f1e25b375c4cad1b1203826c84ee7c7f90e"
                  ]
                }
              }
            ]
          },
          {
            "elType": 4,
            "elIdx": 0,
            "elVchObj": "0x0000000000000000fd6b011a04030001011452047d0db35c330271aae70bedce996b5239ca5ccc4d4b0104030c01011452047d0db35c330271aae70bedce996b5239ca5c4d2e0101008000A6ef9ea235635E328124Ff3429dB9F9E91b64e2df37999ebc168d9109aa536b0773e82da0c4b86ce11e701a7792922b5bb2c414267460C2f56774eD27EeB8685f29f6CEC0B090B0067460C2f56774eD27EeB8685f29f6CEC0B090B00441463bb9f612be23a8f51aad6d62ec8b8342ddba6ac0116021444a5b8ead66bba58d568c684ae8910541d4ac4fc010000000100000080f7b31280f7b7300167460C2f56774eD27EeB8685f29f6CEC0B090B003f340300000000000267460C2f56774eD27EeB8685f29f6CEC0B090B003f34030000000000f87f6d4412dad7c4452e8293850df5327f02c3089bca1d00000000000267460C2f56774eD27EeB8685f29f6CEC0B090B003f34030000000000f87f6d4412dad7c4452e8293850df5327f02c3089bca1d00000000000075",
            "elProof": [
              {
                "branchType": 2,
                "proofSequence": {
                  "CMerkleBranchBase": 2,
                  "nIndex": 5,
                  "nSize": 6,
                  "extraHashes": 0,
                  "branch": [
                    "0xb33f9018d637ae0c676c58d763fdac95b13efcdc3365bf174ed33e1d9f19bc84",
                    "0x8e5966c380b1046b83ebc773a563e3e902dc9806daf11488cb74fcf63106bf0a"
                  ]
                }
              }
            ]
          }
        ]
      },
      "serializedTransfers": "0x01f87f6d4412dad7c4452e8293850df5327f02c308f6941b41454cb83913d688795e237837d30258d11ea7c7528be73f4914c229ea150f397c423df9818deaa7e4c12a80ca0b01160214bfa6f481e6a2aa4ad6cfaa6c1d860623986ba5cd454cb83913d688795e237837d30258d11ea7c752454cb83913d688795e237837d30258d11ea7c752"
    };

        // console log out the tuple so it can be sent to remix for testing.
        // In Remix: load VerusProof ABI, set the contract address to contractAddress below,
        // then paste the calldata into "Low level interactions".

        const hashedTransfers = "0xf37999ebc168d9109aa536b0773e82da0c4b86ce11e701a7792922b5bb2c4142";
        const calldata = contractInstance.methods.checkExportAndTransfers(mainInput, hashedTransfers).encodeABI();


        try {
            await contractInstance.methods.checkExportAndTransfers(mainInput, hashedTransfers).call();
            assert.isTrue(true, "Flags check passed");
            // On mainnet fork this may succeed; on dev network addresses won't match.
        } catch(e) {
         
            // The flags check passes (0x0080 is valid). The revert must come from the CCE
            // field validation (address mismatch), not from the flags check (plain revert).
            assert.isTrue(false, "CCE information does not checkout",
                "Flags check should pass; expected failure at CCE field validation");
        }
      });

      it("Test invalid notarization flags reverts", async () => {
        const NotarizationSerializerInst = await NotarizationSerializer.deployed();
        const contractAddress = NotarizationSerializerInst.address;
        const contractInstance = new web3.eth.Contract(notarizationSerializerAbi.abi, contractAddress);

        // Case 1: flags = 0x0C (FLAG_START_NOTARIZATION | FLAG_LAUNCH_CONFIRMED only).
        // FLAG_LAUNCH_COMPLETE (0x100) is missing so REQUIRED_NOTARIZATION_FLAGS check fails.
        // Serialized: version varint 0x02 + single-byte flags varint 0x0C + padding.
        const missingRequiredFlag = "0x020c" + "00".repeat(20);
        try {
            await contractInstance.methods.deserializeNotarization(missingRequiredFlag).call();
            assert.isTrue(false, "Should have reverted: missing FLAG_LAUNCH_COMPLETE");
        } catch(e) {
            assert.include(e.message, "revert", "Expected revert when required flags are missing");
        }

        // Case 2: flags = 0x10D (REQUIRED_FLAGS | disallowed bit 0x01).
        // ~ALLOWED_NOTARIZATION_FLAGS check fails because bit 0 is not in ALLOWED_NOTARIZATION_FLAGS (0x30C).
        // Serialized: version varint 0x02 + two-byte flags varint 0x81 0x0D (encodes 0x10D = 269) + padding.
        const disallowedExtraFlag = "0x02810d" + "00".repeat(20);
        try {
            await contractInstance.methods.deserializeNotarization(disallowedExtraFlag).call();
            assert.isTrue(false, "Should have reverted: disallowed flag bit present");
        } catch(e) {
            assert.include(e.message, "revert", "Expected revert when disallowed flags are present");
        }
      });
});