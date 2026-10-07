/**
 * bridgeHalt.js
 *
 * Covers the bridge halt states described in docs/BRIDGE-HALT-VOTING.md:
 *   CONTRACTS_TEMPORARY_HALTED   - triggered by notaries revoking themselves, lifted by a quorum of unhalt votes
 *   CONTRACTS_PERMANENTLY_HALTED - lifted only by upgrading (initialize()) the PendingImports contract
 *
 * Run:  ganache-cli -d (deterministic accounts), then  truffle test test/bridgeHalt.js --to 2
 * The dev network has 3 notaries (accounts[1..3]): revoked threshold = min(4, 3) = 3, quorum = 2.
 * Notary recovery signatures use the ganache -d private keys of accounts[1..3].
 */

'use strict';

const crypto            = require('crypto');
const EC                = require('elliptic').ec;
const VerusDelegator    = artifacts.require('../contracts/Main/Delegator.sol');
const MockPermanentHalt = artifacts.require('MockPermanentHalt');
const MockSeedImport    = artifacts.require('MockSeedImport');
const verusDelegatorAbi = require('../build/contracts/Delegator.json');
const pendingImportsAbi = require('../build/contracts/PendingImports.json').abi;
const { getNotarizerIDS } = require('../migrations/setup.js');

const ec = new EC('secp256k1');

const VDXF_DISABLE_CONTRACT_KEY =
    '0x000000000000000000000000b024b1e290c833d9c5703ef6184a7c84e7ddd335';
const IMPORTS_SLOT = 12;
const PENDING_IMPORTS_SLOT = 11;

const FLAGS_NORMAL = '0';
const FLAGS_TEMPORARY_HALT = '6';  // submitImports + sendTransfer (notarizations keep running)
const FLAGS_PERMANENT_HALT = '6';  // submitImports + sendTransfer (notarizations keep running)

const key = (name) => web3.utils.keccak256(name);
const TEMPORARY_HALTED_KEY   = key('bridge.temporary.halted');
const PERMANENTLY_HALTED_KEY = key('bridge.permanently.halted');
const UNHALT_VOTE_BITMAP_KEY = key('bridge.unhalt.vote.bitmap');
const HALT_LIFTED_AT_KEY     = key('bridge.halt.lifted.at');

const HOUR = 3600;
const IMPORT_WINDOW_SECS = HOUR + 24 * HOUR + 60;   // release cooldown + timeout, plus margin

// ganache-cli -d private keys of accounts[1..3] (also the notaries' main and recovery addresses)
const PRIVATE_KEYS = [
    '0x6cbed15c793ce57650b9877cf6fa156fbef513c4e6134f022a85b1ffdd59b2a1',
    '0x6370fd033278c143179d81c5526140625662b8daa446c22ee2d73db3707e620c',
    '0x646f1ce2fdad0e6deeeb5c7e8e5543bdde65e86029e2fd9fc169899c440a7913',
];

const sha256 = (...parts) => crypto.createHash('sha256').update(Buffer.concat(parts)).digest();

// Mirrors NotaryTools.recoverString: sha256 over the hex-string message, then the "Verus signed data:" prefix.
function verusSign(packedHex, privateKey) {
    const message = Buffer.from(packedHex.slice(2).toLowerCase(), 'utf8');
    const inner = sha256(Buffer.from([message.length]), message);
    const digest = sha256(Buffer.from([19]), Buffer.from('Verus signed data:\n', 'utf8'), inner);
    const sig = ec.keyFromPrivate(privateKey.slice(2), 'hex').sign(digest, { canonical: true });
    return {
        v: sig.recoveryParam + 27 + 4,
        r: '0x' + sig.r.toString(16, 64),
        s: '0x' + sig.s.toString(16, 64),
    };
}

const UPGRADE_INFO_TYPE = {
    upgradeInfo: {
        _vs: 'uint8', _rs: 'bytes32', _ss: 'bytes32', contracts: 'address[]',
        upgradeType: 'uint8', salt: 'bytes32', notarizerID: 'address', startHeight: 'uint32',
    },
};

function findEvent(receipt, eventName) {
    const eventAbi = pendingImportsAbi.find(e => e.type === 'event' && e.name === eventName);
    const topic = web3.eth.abi.encodeEventSignature(eventAbi);
    const log = (receipt.logs || []).find(l => l.topics[0] === topic);
    return log ? web3.eth.abi.decodeLog(eventAbi.inputs, log.data, log.topics.slice(1)) : null;
}

const rpc = (method, params = []) =>
    new Promise((resolve, reject) =>
        web3.currentProvider.send({ jsonrpc: '2.0', method, params, id: Date.now() },
            (err, res) => (err ? reject(err) : resolve(res))));

contract('Bridge halt states', async (accounts) => {

    const NOTARIES = [accounts[1], accounts[2], accounts[3]];
    const NOTARY_IDS = getNotarizerIDS('development')[0];
    let DelegatorInst;
    let contractInstance;
    let snapshotId;

    // Raw transactions so receipt.logs keeps events that are not in the Delegator ABI.
    const send = (method, from) => web3.eth.sendTransaction({
        from, to: DelegatorInst.address, data: method.encodeABI(), gas: 6000000,
    });
    const unhaltVote = (voteValue, from) => send(contractInstance.methods.setVerusData(
        web3.eth.abi.encodeParameter('bool', voteValue), 'submitUnhaltVote'), from);
    const revokeSelf = (index) => send(contractInstance.methods.revokeWithMainAddress('0x'), NOTARIES[index]);
    const recover = (index) => {
        const mainAddr = NOTARIES[index].toLowerCase();
        const salt = web3.utils.randomHex(32);
        const packed = '0x03' + mainAddr.slice(2) + mainAddr.slice(2) + salt.slice(2);
        const sig = verusSign(packed, PRIVATE_KEYS[index]);
        const data = web3.eth.abi.encodeParameter(UPGRADE_INFO_TYPE, {
            _vs: sig.v, _rs: sig.r, _ss: sig.s, contracts: [mainAddr, mainAddr],
            upgradeType: 3, salt, notarizerID: NOTARY_IDS[index], startHeight: 0,
        });
        return send(contractInstance.methods.recoverWithRecoveryAddress(data), accounts[0]);
    };

    const expectRevert = async (promise, message) => {
        try {
            await promise;
        } catch (e) {
            assert.include(e.message, 'revert', message);
            return;
        }
        assert.fail('expected revert: ' + message);
    };

    const flags = async () => (await DelegatorInst.claimableFees(VDXF_DISABLE_CONTRACT_KEY)).toString();
    // An unset storageGlobal slot comes back as null (truffle) or '0x' (web3).
    const isSet = async (k) => {
        const v = await DelegatorInst.storageGlobal(k);
        return v !== null && v !== '0x' && v !== '';
    };

    // Each describe starts from the freshly deployed (normal) state.
    const isolate = () => {
        before(async () => { snapshotId = (await rpc('evm_snapshot')).result; });
        after(async () => { await rpc('evm_revert', [snapshotId]); });
    };

    before(async () => {
        DelegatorInst    = await VerusDelegator.deployed();
        contractInstance = new web3.eth.Contract(verusDelegatorAbi.abi, DelegatorInst.address);
        for (const n of NOTARIES) {
            await web3.eth.sendTransaction({ from: accounts[0], to: n, value: web3.utils.toWei('2', 'ether'), gas: 21000 });
        }
    });

    describe('NORMAL', () => {
        isolate();

        it('starts with no halt flags and no halt keys', async () => {
            assert.equal(await flags(), FLAGS_NORMAL);
            assert.isFalse(await isSet(TEMPORARY_HALTED_KEY));
            assert.isFalse(await isSet(PERMANENTLY_HALTED_KEY));
        });

        it('unhalt vote reverts when not halted', async () => {
            await expectRevert(unhaltVote(true, NOTARIES[0]), 'nothing to unhalt');
        });

        it('there is no halt vote endpoint: temporary halts come only from revocations', async () => {
            await expectRevert(send(contractInstance.methods.setVerusData(
                web3.eth.abi.encodeParameter('bool', true), 'submitHaltVote'), NOTARIES[0]), 'submitHaltVote removed');
        });

        it('revoking fewer notaries than the threshold does not halt', async () => {
            await revokeSelf(0);
            await revokeSelf(1);
            assert.equal(await flags(), FLAGS_NORMAL);
            assert.isFalse(await isSet(TEMPORARY_HALTED_KEY));
        });
    });

    describe('CONTRACTS_TEMPORARY_HALTED', () => {
        isolate();

        it('the revocation that reaches the threshold latches the temporary halt', async () => {
            await revokeSelf(0);
            await revokeSelf(1);
            const receipt = await revokeSelf(2);
            assert.ok(findEvent(receipt, 'BridgeTemporarilyHalted'), 'expected BridgeTemporarilyHalted');
            assert.equal(await flags(), FLAGS_TEMPORARY_HALT);
            assert.isTrue(await isSet(TEMPORARY_HALTED_KEY));
            assert.isFalse(await isSet(PERMANENTLY_HALTED_KEY));
        });

        it('sendTransferDirect reverts while halted; the notarization gate bit is not set', async () => {
            await expectRevert(contractInstance.methods.sendTransferDirect('0x')
                .call({ from: accounts[0], gas: 6000000 }), 'sendTransferDirect');
            // HALT_NOTARIZATIONS (bit 0) stays clear so upgrade votes carried in notarizations can still land.
            assert.equal(Number(await flags()) & 1, 0);
        });

        it('revoked notaries cannot vote at all', async () => {
            await expectRevert(unhaltVote(true, NOTARIES[0]), 'revoked notary unhalt vote');
            await expectRevert(unhaltVote(false, NOTARIES[0]), 'revoked notary unhalt rescind');
        });

        it('recovering notaries does not lift the halt', async () => {
            await recover(0);
            await recover(1);
            assert.equal(await flags(), FLAGS_TEMPORARY_HALT);
            assert.isTrue(await isSet(TEMPORARY_HALTED_KEY));
        });

        it('a notary that is still revoked cannot vote, a recovered one can', async () => {
            await expectRevert(unhaltVote(true, NOTARIES[2]), 'still revoked');
            const ev = findEvent(await unhaltVote(true, NOTARIES[0]), 'UnhaltVoteSubmitted');
            assert.equal(ev.voteCount.toString(), '1');
            assert.isTrue(ev.temporarilyHalted);
            assert.equal(await flags(), FLAGS_TEMPORARY_HALT);
        });

        it('an unhalt vote can be rescinded while still halted', async () => {
            const ev = findEvent(await unhaltVote(false, NOTARIES[0]), 'UnhaltVoteSubmitted');
            assert.equal(ev.voteCount.toString(), '0');
            await unhaltVote(true, NOTARIES[0]);
        });

        it('a vote from a notary who was revoked afterwards is not counted', async () => {
            await revokeSelf(0);                                    // notary 0 had voted to unhalt
            const ev = findEvent(await unhaltVote(true, NOTARIES[1]), 'UnhaltVoteSubmitted');
            assert.equal(ev.voteCount.toString(), '1', "revoked notary's vote must not count");
            assert.isTrue(ev.temporarilyHalted);
            assert.equal(await flags(), FLAGS_TEMPORARY_HALT);
        });

        it('a quorum of valid notaries unhalts and clears everything', async () => {
            await recover(0);                                       // notary 0 is valid again, earlier vote counts again
            const receipt = await unhaltVote(true, NOTARIES[0]);
            assert.ok(findEvent(receipt, 'BridgeTemporarilyUnhalted'), 'expected BridgeTemporarilyUnhalted');
            assert.equal(await flags(), FLAGS_NORMAL);
            assert.isFalse(await isSet(TEMPORARY_HALTED_KEY));
            assert.isFalse(await isSet(UNHALT_VOTE_BITMAP_KEY));
            assert.isTrue(await isSet(HALT_LIFTED_AT_KEY), 'unhalt must record when the halt was lifted');
        });

        it('notary 2 is still revoked; revoking two more halts again', async () => {
            await revokeSelf(0);
            assert.equal(await flags(), FLAGS_NORMAL);
            await revokeSelf(1);
            assert.equal(await flags(), FLAGS_TEMPORARY_HALT);
        });
    });

    describe('CONTRACTS_PERMANENTLY_HALTED', () => {
        isolate();
        let originalImports;
        let originalPendingImports;
        const upgradeInto = async (mockAddress) => {
            await DelegatorInst.replacecontract(mockAddress, IMPORTS_SLOT, { from: accounts[0], gas: 6000000 });
            await DelegatorInst.replacecontract(originalImports, IMPORTS_SLOT, { from: accounts[0], gas: 6000000 });
        };

        before(async () => {
            originalImports = await DelegatorInst.contracts(IMPORTS_SLOT);
            originalPendingImports = await DelegatorInst.contracts(PENDING_IMPORTS_SLOT);
        });

        it('is entered with submitImports + sendTransfer halted but notarizations running', async () => {
            const mock = await MockPermanentHalt.new();
            await upgradeInto(mock.address);
            assert.equal(await flags(), FLAGS_PERMANENT_HALT);
            assert.isTrue(await isSet(PERMANENTLY_HALTED_KEY));
            assert.isFalse(await isSet(TEMPORARY_HALTED_KEY));
            assert.equal(
                web3.eth.abi.decodeParameter('bytes32', await DelegatorInst.storageGlobal(PERMANENTLY_HALTED_KEY)),
                '0x' + '0'.repeat(61) + 'bad');
        });

        it('the unhalt endpoint is closed (vote and rescind)', async () => {
            await expectRevert(unhaltVote(true, NOTARIES[0]), 'unhalt vote while permanently halted');
            await expectRevert(unhaltVote(false, NOTARIES[0]), 'unhalt rescind while permanently halted');
            assert.equal(await flags(), FLAGS_PERMANENT_HALT);
        });

        it('revoking notaries does not add a temporary halt (notarizations must keep running)', async () => {
            await revokeSelf(0);
            await revokeSelf(1);
            await revokeSelf(2);
            assert.equal(await flags(), FLAGS_PERMANENT_HALT);
            assert.isFalse(await isSet(TEMPORARY_HALTED_KEY));
        });

        it('upgrading PendingImports (initialize) clears the blocked txid and the halt', async () => {
            await recover(0);
            await recover(1);
            await recover(2);
            await DelegatorInst.replacecontract(originalPendingImports, PENDING_IMPORTS_SLOT, { from: accounts[0], gas: 6000000 });
            assert.equal(await flags(), FLAGS_NORMAL);
            assert.isFalse(await isSet(PERMANENTLY_HALTED_KEY));
            assert.isTrue(await isSet(HALT_LIFTED_AT_KEY), 'lifting the permanent halt must record the lift time');
        });
    });

    describe('Permanent halt lifted while notaries are still revoked', () => {
        isolate();

        it('re-latches the temporary halt immediately instead of waiting for the next revoke', async () => {
            const originalImports = await DelegatorInst.contracts(IMPORTS_SLOT);
            const originalPendingImports = await DelegatorInst.contracts(PENDING_IMPORTS_SLOT);
            const mock = await MockPermanentHalt.new();
            await DelegatorInst.replacecontract(mock.address, IMPORTS_SLOT, { from: accounts[0], gas: 6000000 });
            await DelegatorInst.replacecontract(originalImports, IMPORTS_SLOT, { from: accounts[0], gas: 6000000 });
            await revokeSelf(0);
            await revokeSelf(1);
            await revokeSelf(2);
            assert.isFalse(await isSet(TEMPORARY_HALTED_KEY), 'no temporary halt while permanently halted');

            const receipt = await web3.eth.sendTransaction({
                from: accounts[0], to: DelegatorInst.address, gas: 6000000,
                data: DelegatorInst.contract.methods.replacecontract(originalPendingImports, PENDING_IMPORTS_SLOT).encodeABI(),
            });
            assert.ok(findEvent(receipt, 'BridgeTemporarilyHalted'), 'expected BridgeTemporarilyHalted from initialize()');
            assert.isFalse(await isSet(PERMANENTLY_HALTED_KEY));
            assert.isTrue(await isSet(TEMPORARY_HALTED_KEY));
            assert.equal(await flags(), FLAGS_TEMPORARY_HALT);
        });
    });

    describe('Pending imports across a halt', () => {
        isolate();
        let seeded;

        before(async () => {
            const seed = await MockSeedImport.new();
            seeded = await seed.SEEDED_TXID();
            await DelegatorInst.replacecontract(seed.address, IMPORTS_SLOT, { from: accounts[0], gas: 6000000 });
        });

        const reject = (index) => send(contractInstance.methods.setVerusData(
            web3.eth.abi.encodeParameters(['bytes32', 'bool'], [seeded, false]), 'approveOrRejectAcceptedImport'), NOTARIES[index]);
        const executeTimedOut = () => send(contractInstance.methods.setVerusData(
            web3.eth.abi.encodeParameter('bytes32', seeded), 'executeTimedOutImport'), NOTARIES[1]);

        it('a real reject quorum rejects the import and enters the permanent halt with its txid', async () => {
            const snap = (await rpc('evm_snapshot')).result;
            assert.isNull(findEvent(await reject(0), 'BridgePermanentlyHalted'), 'one reject is not a quorum');
            const receipt = await reject(1);
            const halted = findEvent(receipt, 'BridgePermanentlyHalted');
            assert.ok(halted, 'expected BridgePermanentlyHalted at quorum');
            assert.equal(halted.blockedTxid, seeded);
            assert.ok(findEvent(receipt, 'PendingImportRejected'));
            assert.equal(await flags(), FLAGS_PERMANENT_HALT);
            assert.equal(web3.eth.abi.decodeParameter('bytes32', await DelegatorInst.storageGlobal(PERMANENTLY_HALTED_KEY)), seeded);
            await rpc('evm_revert', [snap]);
        });

        it('lifting a temporary halt restarts the timed-out import clock', async () => {
            await revokeSelf(0);
            await revokeSelf(1);
            await revokeSelf(2);
            await rpc('evm_increaseTime', [IMPORT_WINDOW_SECS]);    // the import is past its timeout, but the bridge is halted
            await rpc('evm_mine');
            await expectRevert(executeTimedOut(), 'timed-out execution while halted');

            await recover(0);
            await recover(1);
            await unhaltVote(true, NOTARIES[0]);
            await unhaltVote(true, NOTARIES[1]);
            assert.equal(await flags(), FLAGS_NORMAL);

            await expectRevert(executeTimedOut(), 'a single notary must not execute an import that sat out the halt');
            await rpc('evm_increaseTime', [IMPORT_WINDOW_SECS]);
            await rpc('evm_mine');
            assert.ok(findEvent(await executeTimedOut(), 'PendingImportReleased'), 'executable after a fresh window');
        });
    });

    describe('Temporary then permanent', () => {
        isolate();

        it('entering a permanent halt clears the temporary halt and its unhalt votes', async () => {
            await revokeSelf(0);
            await revokeSelf(1);
            await revokeSelf(2);
            await recover(0);
            await unhaltVote(true, NOTARIES[0]);                    // 1 of 2 unhalt votes
            assert.equal(await flags(), FLAGS_TEMPORARY_HALT);
            assert.isTrue(await isSet(UNHALT_VOTE_BITMAP_KEY));

            const originalImports = await DelegatorInst.contracts(IMPORTS_SLOT);
            const mock = await MockPermanentHalt.new();
            await DelegatorInst.replacecontract(mock.address, IMPORTS_SLOT, { from: accounts[0], gas: 6000000 });
            await DelegatorInst.replacecontract(originalImports, IMPORTS_SLOT, { from: accounts[0], gas: 6000000 });

            assert.equal(await flags(), FLAGS_PERMANENT_HALT, 'notarizations must be running again');
            assert.isTrue(await isSet(PERMANENTLY_HALTED_KEY));
            assert.isFalse(await isSet(TEMPORARY_HALTED_KEY));
            assert.isFalse(await isSet(UNHALT_VOTE_BITMAP_KEY));
            await expectRevert(unhaltVote(true, NOTARIES[0]), 'unhalt endpoint closed');
        });
    });
});
