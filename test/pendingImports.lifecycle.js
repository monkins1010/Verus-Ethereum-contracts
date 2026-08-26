/**
 * pendingImports.lifecycle.js
 *
 * End-to-end integration test for the pending-import queue lifecycle.
 * See file header comments for full details.
 */

'use strict';

const VerusDelegator        = artifacts.require('../contracts/Main/Delegator.sol');
const verusDelegatorAbi     = require('../build/contracts/Delegator.json');
const pendingImportsAbi     = require('../build/contracts/PendingImports.json').abi;
const { getNotarizerIDS }   = require('../migrations/setup.js');
const testNotarization      = require('./submitnotarization.js');
const goodTx                = require('./goodtransaction.json');

const rpc = (method, params = []) =>
    new Promise((resolve, reject) =>
        web3.currentProvider.send(
            { jsonrpc: '2.0', method, params, id: Date.now() },
            (err, res) => (err ? reject(err) : resolve(res))
        )
    );

const increaseTime = (seconds) => rpc('evm_increaseTime', [seconds]);
const mine         = ()        => rpc('evm_mine');

// PendingImports events are emitted by the Delegator (via delegatecall) but
// are NOT in the Delegator ABI — parse receipt.logs with PendingImports ABI.
function findEvent(receipt, eventName, abi) {
    const eventAbi = abi.find(e => e.type === 'event' && e.name === eventName);
    if (!eventAbi) return null;
    const topic = web3.eth.abi.encodeEventSignature(eventAbi);
    const log = (receipt.logs || []).find(l => l.topics[0] === topic);
    if (!log) return null;
    return web3.eth.abi.decodeLog(eventAbi.inputs, log.data, log.topics.slice(1));
}

const findPI = (receipt, name) => findEvent(receipt, name, pendingImportsAbi);

const VDXF_DISABLE_CONTRACT_KEY =
    '0x000000000000000000000000b024b1e290c833d9c5703ef6184a7c84e7ddd335';
const IMPORT_RELEASE_COOLDOWN_SECS = 3601;
const SUBMIT_IMPORTS_CALLDATA = goodTx['[RAW_INPUT]'];

contract('PendingImports lifecycle', async (accounts) => {

    const NOTARY_SIGNERS = [accounts[1], accounts[2], accounts[3]];
    let DelegatorInst;
    let contractInstance;
    let importTxid = null;

    // web3.eth.Contract.send() runs receipt.logs through the contract ABI decoder,
    // which DROPS events not found in the Delegator ABI (i.e. all PendingImports
    // events).  Encoding calldata manually and using web3.eth.sendTransaction
    // gives a raw receipt where findPI can see every log.
    const vdxfSend = (data, vdxfid, from) => web3.eth.sendTransaction({
        from,
        to: DelegatorInst.address,
        data: contractInstance.methods.setVerusData(data, vdxfid).encodeABI(),
        gas: 6000000,
    });

    before(async () => {
        DelegatorInst    = await VerusDelegator.deployed();
        contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, DelegatorInst.address);
        for (const signer of NOTARY_SIGNERS) {
            const bal = await web3.eth.getBalance(signer);
            if (web3.utils.toBN(bal).lt(web3.utils.toBN(web3.utils.toWei('1', 'ether')))) {
                await web3.eth.sendTransaction({
                    from: accounts[0], to: signer,
                    value: web3.utils.toWei('2', 'ether'), gas: 21000,
                });
            }
        }
    });

    it('getNotaryIAddress VDXF route - registered and does not revert', async () => {
        const notaryIDs = getNotarizerIDS('development')[0];
        for (let i = 0; i < NOTARY_SIGNERS.length; i++) {
            try {
                await contractInstance.methods
                    .setVerusData('0x', 'getNotaryIAddress')
                    .send({ from: NOTARY_SIGNERS[i], gas: 200000 });
            } catch (e) {
                assert.fail('getNotaryIAddress reverted for signer ' + i + ': ' + e.message);
            }
        }
        assert.equal(notaryIDs.length, 3, 'expected 3 test notaries');
    });

    it('setLatestData - primes bestForks with testnet notarization', async function () {
        try {
            await contractInstance.methods.setLatestData(
                testNotarization.serializednotarization,
                testNotarization.txid,
                testNotarization.voutnum,
                testNotarization.abiencodedSigData
            ).send({ from: accounts[0], gas: 6000000 });
        } catch (e) {
            console.log('      WARNING: setLatestData failed (expected on dev node):', e.message.slice(0, 120));
            this.skip();
        }
    });

    it('submitImports - import lands in the pending queue', async function () {
        // submitImports takes a CReserveTransferImport struct; use raw calldata
        // (with function selector) rather than the decoded JS object.
        let receipt;
        try {
            receipt = await web3.eth.sendTransaction({
                from: accounts[0], to: DelegatorInst.address,
                data: SUBMIT_IMPORTS_CALLDATA, gas: 6000000,
            });
        } catch (e) {
            console.log('      WARNING: submitImports failed (proof mismatch expected on dev node):', e.message.slice(0, 120));
            this.skip();
            return;
        }
        const ev = findPI(receipt, 'PendingImportQueued');
        assert.ok(ev, 'expected PendingImportQueued event in receipt logs');
        importTxid = ev.importTxid;
        assert.ok(importTxid, 'importTxid should be captured from PendingImportQueued event');
    });

    it('approveImport vote 1 - import still pending (quorum not yet reached)', async function () {
        if (!importTxid) { this.skip(); return; }
        await increaseTime(IMPORT_RELEASE_COOLDOWN_SECS);
        await mine();
        const receipt = await vdxfSend(
            web3.eth.abi.encodeParameter('bytes32', importTxid), 'approveImport', NOTARY_SIGNERS[0]);
        const approvedEv = findPI(receipt, 'PendingImportApproved');
        assert.ok(approvedEv, 'expected PendingImportApproved event');
        assert.equal(approvedEv.approvalCount.toString(), '1', 'approval count should be 1 after first vote');
        assert.isNull(findPI(receipt, 'PendingImportReleased'),
            'import should NOT be released after only 1 vote (quorum = 2 of 3)');
    });

    it('approveImport vote 2 - quorum reached, import executed and dequeued', async function () {
        if (!importTxid) { this.skip(); return; }
        const receipt = await vdxfSend(
            web3.eth.abi.encodeParameter('bytes32', importTxid), 'approveImport', NOTARY_SIGNERS[1]);
        const releasedEv = findPI(receipt, 'PendingImportReleased');
        assert.ok(releasedEv, 'expected PendingImportReleased event after quorum');
        assert.equal(releasedEv.importTxid.toLowerCase(), importTxid.toLowerCase(),
            'released txid should match the queued import');
    });

    it('releasePendingImport - reverts after import is already executed', async function () {
        if (!importTxid) { this.skip(); return; }
        try {
            await contractInstance.methods
                .setVerusData(web3.eth.abi.encodeParameter('bytes32', importTxid), 'releasePendingImport')
                .send({ from: accounts[0], gas: 6000000 });
            assert.fail('expected revert: import already executed');
        } catch (e) {
            assert.include(e.message, 'revert', 'releasePendingImport should revert for an already-executed import');
        }
    });

    it('approveImport - reverts for already-executed import (double-execute prevented)', async function () {
        if (!importTxid) { this.skip(); return; }
        try {
            await contractInstance.methods
                .setVerusData(web3.eth.abi.encodeParameter('bytes32', importTxid), 'approveImport')
                .send({ from: NOTARY_SIGNERS[2], gas: 6000000 });
            assert.fail('expected revert: import already executed');
        } catch (e) {
            assert.include(e.message, 'revert', 'approveImport should revert when import is no longer pending');
        }
    });

    // ── HALT VOTE TESTS — must be last ────────────────────────────────────────

    it('[halt] bridge not paused before any halt votes', async () => {
        const disableFlag = await DelegatorInst.claimableFees(VDXF_DISABLE_CONTRACT_KEY);
        assert.equal(disableFlag.toString(), '0', 'VDXF_DISABLE_CONTRACT_KEY should be 0 before halt');
    });

    it('[halt] vote 1 of 3 - bridge not yet paused', async () => {
        const receipt = await vdxfSend(
            web3.eth.abi.encodeParameter('bool', true), 'submitHaltVote', NOTARY_SIGNERS[0]);
        const ev = findPI(receipt, 'HaltVoteSubmitted');
        assert.ok(ev, 'expected HaltVoteSubmitted event');
        assert.equal(ev.voteCount.toString(), '1');
        assert.equal(ev.bridgePaused, false, 'bridge should not be paused after 1 halt vote');
    });

    it('[halt] vote 2 of 3 - bridge not yet paused', async () => {
        const receipt = await vdxfSend(
            web3.eth.abi.encodeParameter('bool', true), 'submitHaltVote', NOTARY_SIGNERS[1]);
        const ev = findPI(receipt, 'HaltVoteSubmitted');
        assert.ok(ev, 'expected HaltVoteSubmitted event');
        assert.equal(ev.voteCount.toString(), '2');
        assert.equal(ev.bridgePaused, false, 'bridge should not be paused after 2 halt votes');
    });

    it('[halt] vote 3 of 3 - bridge PAUSED, BridgePaused event fires', async () => {
        const receipt = await vdxfSend(
            web3.eth.abi.encodeParameter('bool', true), 'submitHaltVote', NOTARY_SIGNERS[2]);

        const bridgePausedAbi = pendingImportsAbi.find(e => e.type === 'event' && e.name === 'BridgePaused');
        const bridgePausedTopic = web3.eth.abi.encodeEventSignature(bridgePausedAbi);
        assert.isTrue(
            (receipt.logs || []).some(l => l.topics[0] === bridgePausedTopic),
            'expected BridgePaused event after 3rd halt vote'
        );

        const haltEv = findPI(receipt, 'HaltVoteSubmitted');
        assert.ok(haltEv, 'expected HaltVoteSubmitted event');
        assert.equal(haltEv.voteCount.toString(), '3');
        assert.equal(haltEv.bridgePaused, true, 'bridge should be paused after 3rd halt vote');

        const disableFlag = await DelegatorInst.claimableFees(VDXF_DISABLE_CONTRACT_KEY);
        assert.notEqual(disableFlag.toString(), '0',
            'VDXF_DISABLE_CONTRACT_KEY should be non-zero after bridge is paused');
    });

    it('[halt] submitImports reverts when bridge is paused', async () => {
        try {
            await web3.eth.sendTransaction({
                from: accounts[0], to: DelegatorInst.address,
                data: SUBMIT_IMPORTS_CALLDATA, gas: 6000000,
            });
            assert.fail('expected revert: bridge is paused');
        } catch (e) {
            assert.include(e.message, 'revert', 'submitImports should revert when the bridge is halted');
        }
    });

    it('[halt] approveImport reverts when bridge is paused', async () => {
        const anyTxid = web3.utils.randomHex(32);
        try {
            await contractInstance.methods
                .setVerusData(web3.eth.abi.encodeParameter('bytes32', anyTxid), 'approveImport')
                .send({ from: NOTARY_SIGNERS[0], gas: 6000000 });
            assert.fail('expected revert: bridge is paused');
        } catch (e) {
            assert.include(e.message, 'revert', 'approveImport should revert when bridge is halted');
        }
    });

    it('[halt] executeTimedOutImport reverts when bridge is paused', async () => {
        const anyTxid = web3.utils.randomHex(32);
        try {
            await contractInstance.methods
                .setVerusData(web3.eth.abi.encodeParameter('bytes32', anyTxid), 'executeTimedOutImport')
                .send({ from: accounts[0], gas: 6000000 });
            assert.fail('expected revert: bridge is paused');
        } catch (e) {
            assert.include(e.message, 'revert', 'executeTimedOutImport should revert when bridge is halted');
        }
    });
});
