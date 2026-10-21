'use strict';
/**
 * fixture-notarization.js
 *
 * Submits the two recorded testnet notarizations from test/submitnotarization.js to a deployed
 * Delegator, signed by the first two development notaries (the same flow as deployed.js).
 * After it runs the bridge has a confirmed notarization, so getProof / getExports /
 * getNotarizationData have data to work on.
 *
 * Library:  const { submitFixtureNotarizations } = require('./fixture-notarization.js');
 *           await submitFixtureNotarizations(web3, delegatorAddress, from);
 * CLI:      node testnet/fixture-notarization.js [rpcUrl] [delegatorAddress]
 */

const path = require('path');
const { pbkdf2Sync } = require('crypto');
const { hdkey } = require('ethereumjs-wallet');
const { ecsign } = require('ethereumjs-util');
const { getNotarizerIDS } = require('../migrations/setup.js');
const testNotarization = require('../test/submitnotarization.js');

const MNEMONIC = 'myth like bonus scare over problem client lizard pioneer submit female collect';
const BLOCKHEIGHTS = [2750, 2751];
const VOTE_HASH = '0x9304c78dd2c478a5cd5841dd751dc16baa320603';
const VERUS_PREFIX = '0x01367eaadd291e1976abc446a143f83c2d4d2c5a8401';
const VRSC_ID_HEX = 'a6ef9ea235635e328124ff3429db9f9e91b64e2d';

const serializeUint32 = (value) => {
    const buffer = Buffer.alloc(4);
    buffer.writeUInt32LE(value);
    return buffer.toString('hex');
};

async function submitFixtureNotarizations(web3, delegatorAddress, from) {
    const delegatorAbi = require('../build/contracts/Delegator.json').abi;
    const delegator = new web3.eth.Contract(delegatorAbi, delegatorAddress);
    const [notaryIDs, signers] = getNotarizerIDS('development');
    const notaryAddresses = notaryIDs.slice(0, 2);
    const seed = pbkdf2Sync(MNEMONIC, 'mnemonic', 2048, 64, 'sha512');

    const signingKeys = notaryAddresses.map((id, index) => {
        const wallet = hdkey.fromMasterSeed(seed).derivePath(`m/44'/60'/0'/0/${index + 1}`).getWallet();
        if (wallet.getAddressString().toLowerCase() !== signers[index].toLowerCase()) {
            throw new Error('Fixture signing key does not match development notary ' + index);
        }
        return wallet.getPrivateKey();
    });

    const submit = async (serialized, txid, vout) => {
        const txidHash = web3.utils.keccak256(`${txid}${serializeUint32(vout)}`);
        const notarizationHash = web3.utils.keccak256(serialized);
        const signatures = notaryAddresses.map((notaryID, index) => {
            const digest = web3.utils.keccak256(
                `${VERUS_PREFIX}${txidHash.slice(2)}${VRSC_ID_HEX}${serializeUint32(BLOCKHEIGHTS[index])}` +
                `${notaryID.slice(2)}${notarizationHash.slice(2)}`
            );
            const signature = ecsign(Buffer.from(digest.slice(2), 'hex'), signingKeys[index]);
            return { v: signature.v + 4, r: `0x${signature.r.toString('hex')}`, s: `0x${signature.s.toString('hex')}` };
        });
        const signatureData = web3.eth.abi.encodeParameters(
            ['uint8[]', 'bytes32[]', 'bytes32[]', 'uint32[]', 'address[]'],
            [signatures.map(s => s.v), signatures.map(s => s.r), signatures.map(s => s.s), BLOCKHEIGHTS, notaryAddresses]
        );
        return delegator.methods.setLatestData(serialized, txid, vout, signatureData).send({ from, gas: 6000000 });
    };

    const first = await submit(testNotarization.firstNotarization, testNotarization.firsttxid, testNotarization.firstvout);
    const second = await submit(testNotarization.secondNotarization, testNotarization.secondtxid, testNotarization.secondvout);
    return { first, second, voteHash: VOTE_HASH };
}

module.exports = { submitFixtureNotarizations, VOTE_HASH };

if (require.main === module) {
    const Web3 = require('web3');
    const fs = require('fs');
    const stateFile = path.join(__dirname, '.testnet-state.json');
    const state = fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, 'utf8')) : {};
    const rpcUrl = process.argv[2] || state.rpcUrl || 'http://127.0.0.1:8545';
    const web3 = new Web3(rpcUrl);
    (async () => {
        const accounts = await web3.eth.getAccounts();
        let delegatorAddress = process.argv[3] || state.delegatorAddress;
        if (!delegatorAddress) {
            const artifact = require('../build/contracts/Delegator.json');
            const ids = Object.keys(artifact.networks);
            delegatorAddress = artifact.networks[ids[ids.length - 1]].address;
        }
        await submitFixtureNotarizations(web3, delegatorAddress, accounts[0]);
        console.log('Submitted both fixture notarizations to', delegatorAddress);
    })().catch(e => { console.error(e.message); process.exit(1); });
}
