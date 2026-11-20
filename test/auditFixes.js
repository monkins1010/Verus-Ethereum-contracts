/**
 * auditFixes.js
 *
 * Regression tests for the fixes to findings 1, 4, 5, 6 and 7 of the eaa9a0d1 contract audit
 * (docs: VETH_CONTRACTS_AUDIT_EAA9A0D1_20261118.md).
 *
 * Imports go through the real submitImports -> queue -> notary vote -> release path. Only the Verus proof is
 * stubbed: MockImportProof replaces the VerusProof slot, accepts any import, returns the export heights and
 * exporters the test chooses, and seeds the confirmed-notarization record (proposer, record length).
 *
 * Run:  ganache-cli -d (deterministic accounts), then  truffle test test/auditFixes.js --to 2
 * The dev network has 3 notaries (accounts[1..3]); quorum = 2.
 */

'use strict';

const crypto = require('crypto');
const BNjs = require('bn.js');
const { ReserveTransfer, CurrencyValueMap, TransferDestination, toBase58Check } = require('verus-typescript-primitives');

const VerusDelegator     = artifacts.require('../contracts/Main/Delegator.sol');
const Token              = artifacts.require('Token');
const MockImportProof    = artifacts.require('MockImportProof');
const MockInternalCaller = artifacts.require('MockInternalCaller');
const MockSetStorageGlobal = artifacts.require('MockSetStorageGlobal');
const MockReentrantToken = artifacts.require('MockReentrantToken');
const MockMapToken       = artifacts.require('MockMapToken');
const MockSetClaimableFee = artifacts.require('MockSetClaimableFee');
const pendingImportsAbi  = artifacts.require('PendingImports').abi;

const abi = web3.eth.abi;
const BN = web3.utils.toBN;
const keccak = web3.utils.keccak256;

// dev network (testnet ids)
const VETH = '0x67460C2f56774eD27EeB8685f29f6CEC0B090B00';
const VRSC = '0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d';
const VETH_I = 'iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm';
const VRSC_I = 'iJhCezBExJHvtyH3fGhNnt2NhU4Ztkf2yq';
const ZERO = '0x0000000000000000000000000000000000000000';
const USAGE_CONTRACT = '0xA0f7DC4D7CDe9188818868d11Fa1cd8E34873e56';

const DEST_PKH = 2, DEST_SH = 3, DEST_ID = 4, DEST_REGISTERCURRENCY = 6, DEST_ETH = 9, FLAG_DEST_AUX = 64;
const VALID = 1;

const VERUS_PROOF_SLOT = 2;
const SPARE_SLOT = 9;               // NotarizationSerializer: not used by imports, swapped out and back
const PENDING_IMPORTS_SLOT = 11;
const SATS_TO_WEI = BN('10000000000');
const COIN = 100000000;
const TX_FEE_WEI = '3000000000000000';
const VRSC_FEE_SATS = 2000000;

const NOTARY_FEE_POOL = '0x00000000000000000000000039aDf7BA6E5c91eeef476Bb4aC9417549ba0d51a';
const VDXF_DISABLE_CONTRACT_KEY = '0x000000000000000000000000b024b1e290c833d9c5703ef6184a7c84e7ddd335';
const SUBMIT_IMPORTS_LAST_TXID = '0x00000000000000000000000037256eef64a0bf17344bcb0cbfcde4bea6746347';
const PENDING_IMPORT_QUEUE_INDEX_PREFIX = keccak('pending.import.queue.index');
const PENDING_EXEC_DATA_PREFIX = keccak('pending.exec.data');
const PENDING_IMPORT_KEY_PREFIX = keccak('pending.import');

// The Verus-owned ERC-20 launch vector from reservetransfer.ts; its 5-character name ("chad7") is swapped per launch.
const ERC20_DEFINITION = '0100000020000000a6ef9ea235635e328124ff3429db9f9e91b64e2d056368616437a6ef9ea235635e328124ff3429db9f9e91b64e2da6ef9ea235635e328124ff3429db9f9e91b64e2d0100000001000000000000000000000000000000000000000000000000008a9451000000000000000000012c0d13af98a412ad79e77cfdee70bac119b054fa0080ca396124000000000000000000000000000000000000000000000000a49faec70003f98800';

const ROUTES = ['approveOrRejectAcceptedImport', 'executeTimedOutImport', 'submitUnhaltVote', 'getPendingImports',
    'getPendingImportCount', 'isBridgePaused', 'getNotaryIAddress'];

const rpc = (method, params = []) =>
    new Promise((resolve, reject) =>
        web3.currentProvider.send({ jsonrpc: '2.0', method, params, id: Date.now() },
            (err, res) => (err ? reject(err) : (res.error ? reject(new Error(res.error.message)) : resolve(res)))));

// 22-byte destination key: type(1) | length 20 (1) | address(20)
const destKey = (type, address) => '0x' + type.toString(16).padStart(2, '0') + '14' + address.slice(2).toLowerCase();
// refunds[] mapping key for a destination key: TYPE_REFUND (1) << 244 | key
const refundKey = (key176) => '0x001' + '0'.repeat(61 - (key176.length - 2)) + key176.slice(2);
const claimKey = (key176) => '0x' + '0'.repeat(64 - (key176.length - 2)) + key176.slice(2);

const sha256 = (b) => crypto.createHash('sha256').update(b).digest();
const sha256d = (b) => sha256(sha256(b));
// Mirrors VerusSerializer.checkIAddress
function iAddressOf(name, parentHex = VRSC) {
    const h = sha256d(Buffer.concat([Buffer.from(parentHex.slice(2), 'hex'), sha256d(Buffer.from(name.toLowerCase()))]));
    return crypto.createHash('ripemd160').update(sha256(h)).digest();
}

function payout({ currencyI = VETH_I, amount, to, aux = [], fees = 0 }) {
    return new ReserveTransfer({
        values: new CurrencyValueMap({ valueMap: new Map([[currencyI, new BNjs(amount)]]), multivalue: false }),
        version: new BNjs(1),
        flags: new BNjs(VALID),
        feeCurrencyID: VETH_I,
        feeAmount: new BNjs(fees),
        transferDestination: new TransferDestination({
            type: new BNjs(DEST_ETH + (aux.length ? FLAG_DEST_AUX : 0)),
            destinationBytes: Buffer.from(to.slice(2), 'hex'),
            auxDests: aux.map(([type, address]) => new TransferDestination({
                type: new BNjs(type), destinationBytes: Buffer.from(address.slice(2), 'hex') })),
        }),
        destCurrencyID: VETH_I,
    });
}

function verusTokenLaunch(name) {
    assert.equal(name.length, 5, 'launch names keep the vector\'s length');
    const definition = ERC20_DEFINITION.replace('056368616437', '05' + Buffer.from(name).toString('hex'));
    return new ReserveTransfer({
        values: new CurrencyValueMap({ valueMap: new Map([[toBase58Check(iAddressOf(name), 102), new BNjs(0)]]), multivalue: false }),
        version: new BNjs(1),
        flags: new BNjs(VALID),
        feeCurrencyID: VETH_I,
        feeAmount: new BNjs(0),
        transferDestination: new TransferDestination({
            type: new BNjs(DEST_REGISTERCURRENCY), destinationBytes: Buffer.from(definition, 'hex') }),
        destCurrencyID: VETH_I,
    });
}

function findEvents(receipt, eventName) {
    const eventAbi = pendingImportsAbi.find(e => e.type === 'event' && e.name === eventName);
    const topic = abi.encodeEventSignature(eventAbi);
    return (receipt.logs || []).filter(l => l.topics[0] === topic)
        .map(l => abi.decodeLog(eventAbi.inputs, l.data, l.topics.slice(1)));
}

contract('Audit eaa9a0d1 fixes', async (accounts) => {

    const OWNER = accounts[0];
    const NOTARIES = [accounts[1], accounts[2], accounts[3]];
    const USER = accounts[5];
    const PAYEE = accounts[6];
    const PAYEE2 = accounts[7];
    const PKH_A = '0x' + 'a1'.repeat(20);
    const PKH_B = '0x' + 'b2'.repeat(20);
    const SH_S = '0x' + 'c3'.repeat(20);
    const EXPORTER = destKey(DEST_PKH, '0x' + 'e4'.repeat(20));
    const PKH_PROPOSER = destKey(DEST_PKH, '0x' + 'd5'.repeat(20));

    let delegator;
    let web3Delegator;
    let rejecter;       // a contract without receive(): a vETH payout to it fails
    let snapshotId;

    const isolate = () => {
        before(async () => { snapshotId = (await rpc('evm_snapshot')).result; });
        after(async () => { await rpc('evm_revert', [snapshotId]); });
    };

    const send = (method, from, value = '0', gas = 15000000) => web3.eth.sendTransaction({
        from, to: delegator.address, data: method.encodeABI(), gas, value,
    });
    const expectRevert = async (promise, message) => {
        try {
            await promise;
        } catch (e) {
            assert.include(e.message, 'revert', message);
            return;
        }
        assert.fail('expected revert: ' + message);
    };

    const tokenIndex = async (currency) => BN((await delegator.verusToERC20mapping(currency)).tokenIndex);
    const refund = async (key176, currency) => BN(await delegator.refunds(refundKey(key176), currency));
    const claimable = async (key) => BN(await delegator.claimableFees(key));
    const isEmpty = (bytes) => !bytes || bytes === '0x';

    // Deposit vETH the pre-launch way (fees in VRSC), so the bridge holds ETH and tokenIndex[VETH] counts it.
    const deposit = async (coins) => {
        const amount = coins * COIN;
        const transfer = {
            version: 1, currencyvalue: { currency: VETH, amount }, flags: 1, feecurrencyid: VRSC, fees: VRSC_FEE_SATS,
            destination: { destinationtype: DEST_PKH, destinationaddress: PKH_A }, destcurrencyid: VRSC,
            destsystemid: ZERO, secondreserveid: ZERO,
        };
        await send(web3Delegator.methods.sendTransfer(transfer), USER,
            BN(amount).mul(SATS_TO_WEI).add(BN(TX_FEE_WEI)).toString());
    };

    const nextStartHeight = async () => {
        const last = await delegator.lastImportInfo(SUBMIT_IMPORTS_LAST_TXID);
        return Number(last.height) + 1;
    };

    // Submits an import through the real submitImports. Returns its txid.
    const submitImport = async (transfers, { width = 0, inverted = false, proposer = PKH_PROPOSER, forksLength = 128, launched = false } = {}) => {
        const start = await nextStartHeight();
        const end = inverted ? start - 1 : start + width;
        const cce = BN(start).or(BN(end).shln(32)).or(BN(1).shln(64)).or(BN(transfers.length).shln(96));
        const proof = await MockImportProof.new(cce.toString(), 0, EXPORTER, proposer, forksLength, launched);
        await delegator.replacecontract(proof.address, VERUS_PROOF_SLOT, { from: OWNER, gas: 6000000 });

        const txid = web3.utils.randomHex(32);
        // CTransactionHeader: txid, struct version 1, nVersion, nVersionGroupId, nVins 0, nVouts 1, no shielded parts
        const header = txid + '01' + '04000080' + '00000000' + '00000000' + '01000000' + '00000000' + '00000000';
        const serialized = '0x' + Buffer.concat(transfers.map(t => t.toBuffer())).toString('hex');
        const importData = {
            partialtransactionproof: {
                version: 1, typeC: 2,
                txproof: [{ branchType: 2, proofSequence: { CMerkleBranchBase: 2, nIndex: 0, nSize: 1, extraHashes: 0, branch: [] } }],
                components: [{ elType: 1, elIdx: 0, elVchObj: header, elProof: [] }],
            },
            serializedTransfers: serialized,
        };
        await send(web3Delegator.methods.submitImports(importData), OWNER);
        return txid;
    };

    const vote = (txid, approve, from) => send(web3Delegator.methods.setVerusData(
        abi.encodeParameters(['bytes32', 'bool'], [txid, approve]), 'approveOrRejectAcceptedImport'), from);

    // Waits out the release cooldown and casts the two approvals that make quorum. Returns the releasing receipt.
    const release = async (txid) => {
        await rpc('evm_increaseTime', [3601]);
        await rpc('evm_mine');
        await vote(txid, true, NOTARIES[0]);
        const receipt = await vote(txid, true, NOTARIES[1]);
        assert.equal(findEvents(receipt, 'PendingImportReleased').length, 1, 'import released');
        return receipt;
    };

    before(async () => {
        delegator = await VerusDelegator.deployed();
        web3Delegator = new web3.eth.Contract(VerusDelegator.abi, delegator.address);
        rejecter = await Token.new('NoEth', 'NOETH');
        await deposit(20);
    });

    // ------------------------------------------------------------------------------------------------
    describe('Finding 1: setVerusData resolves only the fixed route names', () => {
        isolate();

        const checkVDFXId = async (nameHex) => {
            const cce = await delegator.contracts(3);
            const data = abi.encodeFunctionSignature('checkVDFXId(string)') + abi.encodeParameter('bytes', nameHex).slice(2);
            return web3.eth.call({ to: cce, data });
        };

        it('every route name resolves to PendingImports', async () => {
            for (const name of ROUTES) {
                const raw = await checkVDFXId(web3.utils.utf8ToHex(name));
                assert.equal(abi.decodeParameter('uint256', raw).toString(), String(PENDING_IMPORTS_SLOT), name);
            }
        });

        it('a queued import\'s queue-index record is not a route, although it holds a valid contract index', async () => {
            const txid = await submitImport([payout({ amount: COIN, to: PAYEE })]);
            const preimage = PENDING_IMPORT_QUEUE_INDEX_PREFIX + txid.slice(2);
            // The record exists and decodes to a contract index, which is what the old resolver returned.
            const record = await delegator.storageGlobal(keccak(preimage));
            assert.isAbove(record.length, 2, 'queue index record present');
            assert.isBelow(Number(abi.decodeParameter('uint256', record)), 13, 'record decodes to a contract index');

            await expectRevert(checkVDFXId(preimage), 'checkVDFXId of a data key');
            const calldata = abi.encodeFunctionSignature('setVerusData(bytes,string)') +
                abi.encodeParameters(['bytes', 'bytes'], ['0x', preimage]).slice(2);
            await expectRevert(web3.eth.sendTransaction({ from: USER, to: delegator.address, data: calldata, gas: 3000000 }),
                'setVerusData with a data key as the route');
        });

        // A data record whose key is keccak256(name) of a logic function. The audit reaches this with a 2^32 search
        // over a txid-derived key; writing the record directly is the same state without the search.
        const plantRecord = async (name, contractIndex) => {
            const original = await delegator.contracts(SPARE_SLOT);
            const planter = await MockSetStorageGlobal.new(keccak(name), contractIndex);
            await delegator.replacecontract(planter.address, SPARE_SLOT, { from: OWNER, gas: 6000000 });
            await delegator.replacecontract(original, SPARE_SLOT, { from: OWNER, gas: 6000000 });
        };
        const exportSetSize = async () => {
            const start = await delegator.cceLastStartHeight();
            const exports = await web3Delegator.methods.getReadyExportsByRange(start.toString(), start.toString()).call();
            return exports.length ? exports[0].transfers.length : 0;
        };

        it('a colliding data record does not route a non-notary to externalCreateExportCallPayable (unpaid export)', async () => {
            await plantRecord('externalCreateExportCallPayable', 5);
            const before = await exportSetSize();
            const unpaid = {
                version: 1, currencyvalue: { currency: VETH, amount: '100000000000000' }, flags: 1, feecurrencyid: VETH, fees: 0,
                destination: { destinationtype: DEST_PKH, destinationaddress: PKH_A }, destcurrencyid: VRSC,
                destsystemid: ZERO, secondreserveid: ZERO,
            };
            const data = abi.encodeParameters(
                ['tuple(uint32,tuple(address,uint64),uint32,address,uint64,tuple(uint8,bytes),address,address,address)', 'bool'],
                [[unpaid.version, [VETH, unpaid.currencyvalue.amount], 1, VETH, 0, [DEST_PKH, PKH_A], VRSC, ZERO, ZERO], false]);
            await expectRevert(send(web3Delegator.methods.setVerusData(data, 'externalCreateExportCallPayable'), USER),
                'route through a colliding data record');
            assert.equal(await exportSetSize(), before, 'nothing appended to the export set');
        });

        it('a colliding data record does not make any other logic function a route (allowlist alone)', async () => {
            // NotaryTools.revokeWithMainAddress(bytes) has no flow guard and succeeds for a valid notary, so only the
            // route allowlist can refuse it.
            await plantRecord('revokeWithMainAddress', 6);
            await expectRevert(send(web3Delegator.methods.setVerusData('0x', 'revokeWithMainAddress'), NOTARIES[2]),
                'revokeWithMainAddress as a route');
            const notaryIds = [];
            for (let i = 0; i < 3; i++) notaryIds.push(await delegator.notaries(i));
            for (const id of notaryIds) {
                assert.equal((await delegator.notaryAddressMapping(id)).state.toString(), '1', 'no notary revoked');
            }
        });

        it('other stored keys are not routes either', async () => {
            for (const name of ['PendingImports.contract.index', 'Imports.contract.index', 'haltBridge', 'resumeBridge',
                                'pending.import.nonce.counter', 'bridge.unhalt.vote.bitmap', 'initialize']) {
                await expectRevert(checkVDFXId(web3.utils.utf8ToHex(name)), name);
            }
        });
    });

    // ------------------------------------------------------------------------------------------------
    describe('Finding 1: internal-only logic functions refuse calls outside their flow', () => {
        isolate();

        const result = async (name) => abi.decodeParameter('bool', await delegator.storageGlobal(keccak(web3.utils.utf8ToHex('mock.internal.' + name))));

        before(async () => {
            await submitImport([payout({ amount: COIN, to: PAYEE })]);   // seeds the notarization record
            const original = await delegator.contracts(SPARE_SLOT);
            const caller = await MockInternalCaller.new(VETH);
            await delegator.replacecontract(caller.address, SPARE_SLOT, { from: OWNER, gas: 6000000 });
            await delegator.replacecontract(original, SPARE_SLOT, { from: OWNER, gas: 6000000 });
        });

        const GUARDED = ['processTransactions', 'recordToken', 'queuePendingImport', 'externalCreateExportCallPayable',
            'launchContractTokens', 'executePendingImport', 'payOutImport', 'payRefundOnETH', 'sendCurrencyToETHAddress',
            'checkExport', 'join', 'exit', 'daiBalance', 'generateCCE', 'externalCreateExportCall'];
        // Calls whose inputs are valid, so they succeed once their flow is active: the guard is what refused them.
        const SUCCEED_WITH_FLOW = ['processTransactions', 'recordToken', 'queuePendingImport', 'externalCreateExportCallPayable',
            'payOutImport', 'payRefundOnETH', 'sendCurrencyToETHAddress', 'join', 'exit', 'daiBalance'];

        it('each internal-only function reverts without its flow', async () => {
            for (const name of GUARDED) {
                assert.isFalse(await result(name), name + ' must refuse a call outside its flow');
            }
        });

        it('the same calls succeed with the flow set (control)', async () => {
            for (const name of SUCCEED_WITH_FLOW) {
                assert.isTrue(await result(name + '.withFlow'), name + ' should succeed inside its flow');
            }
        });

        it('generateCCE refuses delegatecall even with a flow; externalCreateExportCall is gone; launchContractTokens is closed', async () => {
            assert.isFalse(await result('generateCCE.withFlow'));
            assert.isFalse(await result('externalCreateExportCall.withFlow'));
            assert.isFalse(await result('launchContractTokens.withFlow'), 'tokenList already populated');
        });

        it('no flow is left set after a transaction', async () => {
            assert.equal((await claimable(keccak('veth.internal.call.flow'))).toString(), '0');
        });
    });

    // ------------------------------------------------------------------------------------------------
    describe('Findings 4 and 6: payout failures stay local; refunds use a payable key', () => {
        isolate();
        let receipt;
        let payeeBefore;
        let indexBefore;

        before(async () => {
            payeeBefore = BN(await web3.eth.getBalance(PAYEE));
            indexBefore = await tokenIndex(VETH);
            const txid = await submitImport([
                payout({ amount: COIN, to: PAYEE, aux: [[DEST_PKH, PKH_A]] }),                        // paid
                payout({ amount: 2 * COIN, to: rejecter.address, aux: [[DEST_SH, SH_S], [DEST_PKH, PKH_B]] }), // refund, PKH_B
                payout({ amount: 3 * COIN, to: rejecter.address, aux: [[DEST_SH, SH_S]] }),            // refund, ETH key
                payout({ currencyI: VRSC_I, amount: COIN, to: ZERO, aux: [[DEST_SH, SH_S]] }),          // refund, SH (VRSC)
            ]);
            receipt = await release(txid);
        });

        it('the batch releases and the good payout is made', async () => {
            assert.equal(BN(await web3.eth.getBalance(PAYEE)).sub(payeeBefore).toString(), BN(COIN).mul(SATS_TO_WEI).toString());
            assert.equal(indexBefore.sub(await tokenIndex(VETH)).toString(), String(COIN), 'only the paid amount leaves custody');
        });

        it('a non-VRSC refund skips the P2SH aux and uses the next payable one', async () => {
            assert.equal((await refund(destKey(DEST_PKH, PKH_B), VETH)).toString(), String(2 * COIN));
            assert.equal((await refund(destKey(DEST_SH, SH_S), VETH)).toString(), '0', 'nothing stranded under P2SH');
        });

        it('a non-VRSC refund whose only aux is P2SH falls back to the Ethereum destination', async () => {
            assert.equal((await refund(destKey(DEST_ETH, rejecter.address), VETH)).toString(), String(3 * COIN));
        });

        it('a VRSC refund may still use the P2SH aux', async () => {
            assert.equal((await refund(destKey(DEST_SH, SH_S), VRSC)).toString(), String(COIN));
        });
    });

    describe('Finding 4 and 3: a payout above the custody ledger neither reverts the release nor leaves an unbacked refund', () => {
        isolate();

        it('releases; the over-ledger payout is undone, not refunded, and the rest of the batch is paid', async () => {
            // ETH sent outside sendTransfer is held but not counted in tokenIndex.
            await web3.eth.sendTransaction({ from: USER, to: delegator.address, value: web3.utils.toWei('30'), gas: 100000 });
            const ledger = await tokenIndex(VETH);
            const tooMuch = ledger.addn(1);
            const payee2Before = BN(await web3.eth.getBalance(PAYEE2));
            const payeeBefore = BN(await web3.eth.getBalance(PAYEE));

            const txid = await submitImport([
                payout({ amount: tooMuch.toString(), to: PAYEE2, aux: [[DEST_PKH, PKH_A]] }),
                payout({ amount: COIN, to: PAYEE, aux: [[DEST_PKH, PKH_B]] }),
            ]);
            const receipt = await release(txid);

            assert.equal(BN(await web3.eth.getBalance(PAYEE2)).sub(payee2Before).toString(), '0', 'over-ledger payout undone');
            assert.equal((await refund(destKey(DEST_PKH, PKH_A), VETH)).toString(), '0', 'no refund custody cannot back');
            const notBacked = receipt.logs.filter(l => l.topics[0] === keccak(web3.utils.utf8ToHex('RefundNotBacked(uint176,address,uint256)')));
            assert.equal(notBacked.length, 1, 'RefundNotBacked emitted');
            assert.equal(BN(await web3.eth.getBalance(PAYEE)).sub(payeeBefore).toString(), BN(COIN).mul(SATS_TO_WEI).toString());
            assert.equal((await tokenIndex(VETH)).toString(), ledger.sub(BN(COIN)).toString());
        });
    });

    describe('Finding 3: every refund in a held currency is backed by custody', () => {
        isolate();
        const backing = async (currency) => claimable('0x' + BN(keccak(web3.utils.utf8ToHex('refund.backing')))
            .xor(BN(currency)).toString(16).padStart(64, '0'));
        let half;

        it('refunds are recorded while all outstanding refunds fit in custody, and not beyond', async () => {
            const ledger = await tokenIndex(VETH);
            half = ledger.divn(2);
            // Both payouts fail (the recipient refuses ETH). Each alone fits in custody; together they do not.
            const txid = await submitImport([
                payout({ amount: half.toString(), to: rejecter.address, aux: [[DEST_ETH, PAYEE2]] }),
                payout({ amount: ledger.sub(half).addn(1).toString(), to: rejecter.address, aux: [[DEST_PKH, PKH_B]] }),
            ], { launched: true });
            await release(txid);
            assert.equal((await refund(destKey(DEST_ETH, PAYEE2), VETH)).toString(), half.toString(), 'first refund recorded');
            assert.equal((await refund(destKey(DEST_PKH, PKH_B), VETH)).toString(), '0', 'second refund would exceed custody');
            assert.equal((await backing(VETH)).toString(), half.toString(), 'outstanding refunds counted');
        });

        it('claiming a refund releases its backing, so a later refund fits again', async () => {
            await send(web3Delegator.methods.claimRefund(destKey(DEST_ETH, PAYEE2), VETH), USER);
            assert.equal((await backing(VETH)).toString(), '0', 'backing released on claim');
            const ledger = await tokenIndex(VETH);   // custody after paying the claim
            const txid = await submitImport([payout({ amount: ledger.toString(), to: rejecter.address, aux: [[DEST_PKH, PKH_A]] })],
                { launched: true });
            await release(txid);
            assert.equal((await refund(destKey(DEST_PKH, PKH_A), VETH)).toString(), ledger.toString(),
                'recorded: without the release on claim it would not fit');
        });

        it('a refund custody no longer covers cannot be claimed', async () => {
            // A payout that succeeds still draws on custody that outstanding refunds count on (only a broken export
            // can do this); the refund then exceeds custody and its claim reverts, leaving it recorded.
            // A vETH refund sent back to Verus pays its fee from the refund, priced from the notarized reserves:
            // seed vETH = VRSC = 1 (fee 0.04 vETH).
            const reservesKey = '0x' + '0'.repeat(24) + '1b83ebe56d691b909cfb0dfc291e5a0edaafc64c';
            const reserves = BN(COIN).or(BN(COIN).shln(128)).toString();
            const original = await delegator.contracts(SPARE_SLOT);
            const seeder = await MockSetClaimableFee.new(reservesKey, reserves);
            await delegator.replacecontract(seeder.address, SPARE_SLOT, { from: OWNER, gas: 6000000 });
            await delegator.replacecontract(original, SPARE_SLOT, { from: OWNER, gas: 6000000 });

            const outstanding = await refund(destKey(DEST_PKH, PKH_A), VETH);
            const claim = () => send(web3Delegator.methods.claimRefund(destKey(DEST_PKH, PKH_A), VETH), USER);
            // control: while custody covers it, the same claim succeeds
            const snap = (await rpc('evm_snapshot')).result;
            await claim();
            assert.equal((await refund(destKey(DEST_PKH, PKH_A), VETH)).toString(), '0', 'control claim paid');
            await rpc('evm_revert', [snap]);

            const txid = await submitImport([payout({ amount: (await tokenIndex(VETH)).toString(), to: PAYEE })], { launched: true });
            await release(txid);
            assert.equal((await tokenIndex(VETH)).toString(), '0');
            await expectRevert(claim(), 'claim of an uncovered refund');
            assert.equal((await refund(destKey(DEST_PKH, PKH_A), VETH)).toString(), outstanding.toString(), 'refund kept');
        });
    });

    describe('Finding 2: an import fee outside the range is not counted and cannot block the queue', () => {
        isolate();
        const MAX_FEE = 1000000000;   // VerusSerializer.MAX_IMPORT_FEE_PER_TRANSFER, 10 vETH

        it('a fee above the per-transfer range is not counted', async () => {
            const poolBefore = await claimable(NOTARY_FEE_POOL);
            const txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: MAX_FEE + 1 })]);
            await release(txid);
            assert.equal((await claimable(NOTARY_FEE_POOL)).sub(poolBefore).toString(), '0', 'nothing credited from the fee');
        });

        it('control: a fee at the top of the range is counted', async () => {
            const poolBefore = await claimable(NOTARY_FEE_POOL);
            const txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: MAX_FEE })]);
            await release(txid);
            assert.isTrue((await claimable(NOTARY_FEE_POOL)).gt(poolBefore), 'fee credited');
        });

        it('fees summing past 2^64 no longer stop the import being queued', async () => {
            const huge = '9223372036854775808';   // 2^63, twice is 2^64
            const txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: huge }), payout({ amount: COIN, to: PAYEE, fees: huge })]);
            await release(txid);
        });
    });

    describe('Findings 4 and 7: fee split cannot revert the release; proposer share is type-filtered', () => {
        isolate();
        const FEES = 20000000;   // 0.2 vETH: enough above the gas cost that processors' fees are split

        it('an export whose end height is below its start height releases', async () => {
            const txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: FEES })], { inverted: true });
            await release(txid);
        });

        it('a confirmed-notarization record too short for the proposer releases; the share goes to the pool', async () => {
            const poolBefore = await claimable(NOTARY_FEE_POOL);
            const txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: FEES })], { forksLength: 96 });
            await release(txid);
            assert.isTrue((await claimable(NOTARY_FEE_POOL)).gt(poolBefore));
        });

        it('a P2SH proposer is not credited; a PKH proposer is', async () => {
            const shProposer = destKey(DEST_SH, '0x' + 'f6'.repeat(20));
            let txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: FEES })], { proposer: shProposer });
            await release(txid);
            assert.equal((await claimable(claimKey(shProposer))).toString(), '0', 'P2SH proposer key not credited');

            txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: FEES })], { proposer: PKH_PROPOSER });
            await release(txid);
            assert.isTrue((await claimable(claimKey(PKH_PROPOSER))).gtn(0), 'PKH proposer credited');
        });

        it('getProof credits a P2SH proposer\'s share to the pool, a PKH proposer\'s to the proposer', async () => {
            const shProposer = destKey(DEST_SH, '0x' + 'f7'.repeat(20));
            await submitImport([payout({ amount: COIN, to: PAYEE })], { proposer: shProposer });  // reseeds the record
            const poolBefore = await claimable(NOTARY_FEE_POOL);
            await send(web3Delegator.methods.getProof(0), USER, web3.utils.toWei('0.01'));
            assert.equal((await claimable(claimKey(shProposer))).toString(), '0');
            assert.equal((await claimable(NOTARY_FEE_POOL)).sub(poolBefore).toString(), '1000000', 'both halves to the pool');

            const before = await claimable(claimKey(PKH_PROPOSER));
            await submitImport([payout({ amount: COIN, to: PAYEE })], { proposer: PKH_PROPOSER });
            await send(web3Delegator.methods.getProof(0), USER, web3.utils.toWei('0.01'));
            assert.equal((await claimable(claimKey(PKH_PROPOSER))).sub(before).toString(), '500000');
        });

        it('a protocol-share recipient that refuses ETH does not revert the release', async () => {
            // control: the share is sent and leaves custody
            let usageBefore = BN(await web3.eth.getBalance(USAGE_CONTRACT));
            let indexBefore = await tokenIndex(VETH);
            let txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: FEES })]);
            await release(txid);
            const share = BN(await web3.eth.getBalance(USAGE_CONTRACT)).sub(usageBefore).div(SATS_TO_WEI);
            assert.isTrue(share.gtn(0), 'protocol share sent');
            assert.equal(indexBefore.sub(await tokenIndex(VETH)).toString(), share.add(BN(COIN)).toString());

            // refusing recipient: release still succeeds, the share stays in custody and goes to the pool
            await rpc('evm_setAccountCode', [USAGE_CONTRACT, '0x60006000fd']);   // PUSH1 0 PUSH1 0 REVERT
            usageBefore = BN(await web3.eth.getBalance(USAGE_CONTRACT));
            indexBefore = await tokenIndex(VETH);
            txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: FEES })]);
            await release(txid);
            assert.equal(BN(await web3.eth.getBalance(USAGE_CONTRACT)).sub(usageBefore).toString(), '0');
            assert.equal(indexBefore.sub(await tokenIndex(VETH)).toString(), String(COIN), 'only the payout left custody');
            await rpc('evm_setAccountCode', [USAGE_CONTRACT, '0x']);
        });
    });

    describe('Finding 6: vETH fee refunds are credited only to keys claimRefund pays', () => {
        isolate();

        it('a P2SH refund key gets no fee refund; PKH keys do', async () => {
            const FEES = 2000000;
            const shKey = destKey(DEST_SH, SH_S);
            const txid = await submitImport([
                payout({ amount: COIN, to: PAYEE, aux: [[DEST_PKH, PKH_A]], fees: FEES }),
                payout({ amount: COIN, to: PAYEE, aux: [[DEST_PKH, PKH_A]], fees: FEES }),
                payout({ amount: COIN, to: PAYEE, aux: [[DEST_PKH, PKH_B]], fees: FEES }),
                payout({ amount: COIN, to: PAYEE, aux: [[DEST_PKH, PKH_B]], fees: FEES }),
                payout({ currencyI: VRSC_I, amount: COIN, to: PAYEE2, aux: [[DEST_SH, SH_S]], fees: FEES }),
            ], { width: 2 });   // multi-block export: fee refunds above 4 transfers
            await release(txid);
            assert.isTrue((await refund(destKey(DEST_PKH, PKH_A), VETH)).gtn(0), 'PKH fee refund');
            assert.isTrue((await refund(destKey(DEST_PKH, PKH_B), VETH)).gtn(0), 'PKH fee refund');
            assert.equal((await refund(shKey, VETH)).toString(), '0', 'no vETH credited to a P2SH key');
        });
    });

    describe('Finding 5: launches per import are capped', () => {
        isolate();

        it('an import with 5 Verus-owned ERC-20 launches maps the first 4, skips the 5th, and still pays', async () => {
            const names = ['tok01', 'tok02', 'tok03', 'tok04', 'tok05'];
            const payeeBefore = BN(await web3.eth.getBalance(PAYEE));
            const txid = await submitImport([...names.map(verusTokenLaunch), payout({ amount: COIN, to: PAYEE })]);
            const receipt = await release(txid);
            for (let i = 0; i < names.length; i++) {
                const mapping = await delegator.verusToERC20mapping('0x' + iAddressOf(names[i]).toString('hex'));
                if (i < 4) {
                    assert.notEqual(mapping.flags.toString(), '0', names[i] + ' launched');
                } else {
                    assert.equal(mapping.flags.toString(), '0', names[i] + ' over the cap, not launched');
                }
            }
            assert.equal(BN(await web3.eth.getBalance(PAYEE)).sub(payeeBefore).toString(), BN(COIN).mul(SATS_TO_WEI).toString());
            assert.isBelow(receipt.gasUsed, 10000000, 'release gas stays bounded');
        });
    });

    // ------------------------------------------------------------------------------------------------
    describe('Finding 1: a token callback cannot use the flow that is active while the bridge calls it', () => {
        isolate();

        const HOSTILE = '0x' + '9e'.repeat(20);                 // Verus currency id mapped to the hostile token
        const HOSTILE_I = toBase58Check(Buffer.from(HOSTILE.slice(2), 'hex'), 102);
        const MAPPING_ETHEREUM_OWNED_ERC20 = 1 | 32;
        const FLOW_KEY = keccak(web3.utils.utf8ToHex('veth.internal.call.flow'));
        const IMPORTS_SLOT = 12, EXPORT_MANAGER_SLOT = 7;
        const ONE_TOKEN = BN(COIN).mul(SATS_TO_WEI).toString();  // 18 decimals: 1 Verus unit = 1e18

        let hostile;
        let calls;

        // Transfers in every export set so far.
        const exportedTransfers = async () => {
            const latest = await web3.eth.getBlockNumber();
            const exports = await web3Delegator.methods.getReadyExportsByRange('0', String(latest + 1)).call();
            return exports.reduce((n, e) => n + e.transfers.length, 0);
        };
        const readRecord = async () => {
            const record = BN(await hostile.record());
            return { ran: record.andln(2) === 2, flow: record.shrn(8).andln(0xff), succeeded: record.shrn(16).toString(2) };
        };
        const encodeCall = (signature, types, values) => abi.encodeFunctionSignature(signature) + abi.encodeParameters(types, values).slice(2);
        const arm = (list) => hostile.arm(list.map(c => c.to), list.map(c => c.data), list.map(c => c.value || '0'));

        before(async () => {
            hostile = await MockReentrantToken.new(delegator.address, USER, BN(ONE_TOKEN).muln(10).toString());
            await web3.eth.sendTransaction({ from: USER, to: hostile.address, value: web3.utils.toWei('1'), gas: 100000 });
            const original = await delegator.contracts(SPARE_SLOT);
            const mapper = await MockMapToken.new(HOSTILE, hostile.address, MAPPING_ETHEREUM_OWNED_ERC20);
            await delegator.replacecontract(mapper.address, SPARE_SLOT, { from: OWNER, gas: 6000000 });
            await delegator.replacecontract(original, SPARE_SLOT, { from: OWNER, gas: 6000000 });

            const imports = await delegator.contracts(IMPORTS_SLOT);
            const exportManager = await delegator.contracts(EXPORT_MANAGER_SLOT);
            const vethDeposit = {
                version: 1, currencyvalue: { currency: VETH, amount: COIN }, flags: 1, feecurrencyid: VRSC, fees: VRSC_FEE_SATS,
                destination: { destinationtype: DEST_PKH, destinationaddress: PKH_A }, destcurrencyid: VRSC,
                destsystemid: ZERO, secondreserveid: ZERO,
            };
            const route = (name, data = '0x') => ({ to: delegator.address, data: web3Delegator.methods.setVerusData(data, name).encodeABI() });
            calls = {
                checkExportRoute: route('checkExport'),
                createExportRoute: route('externalCreateExportCallPayable'),
                sendTransfer: { to: delegator.address, data: web3Delegator.methods.sendTransfer(vethDeposit).encodeABI(),
                                value: BN(COIN).mul(SATS_TO_WEI).add(BN(TX_FEE_WEI)).toString() },
                payOutImportDirect: { to: imports, data: encodeCall('payOutImport(address,address,uint64)',
                    ['address', 'address', 'uint64'], [USER, VETH, '1']) },
                sendCurrencyDirect: { to: exportManager, data: encodeCall('sendCurrencyToETHAddress(address,address,uint256,uint32,uint256)',
                    ['address', 'address', 'uint256', 'uint32', 'uint256'], [hostile.address, USER, '1', '0xa9059cbb', '0']) },
            };
        });

        it('deposit: during transferFrom (SEND_TRANSFER flow) every re-entry is refused, and the deposit completes once', async () => {
            await arm([calls.checkExportRoute, calls.createExportRoute, calls.sendTransfer, calls.payOutImportDirect, calls.sendCurrencyDirect]);
            await hostile.approve(delegator.address, ONE_TOKEN, { from: USER });
            const before = await exportedTransfers();
            const deposit = {
                version: 1, currencyvalue: { currency: HOSTILE, amount: COIN }, flags: 1, feecurrencyid: VRSC, fees: VRSC_FEE_SATS,
                destination: { destinationtype: DEST_PKH, destinationaddress: PKH_A }, destcurrencyid: VRSC,
                destsystemid: ZERO, secondreserveid: ZERO,
            };
            await send(web3Delegator.methods.sendTransfer(deposit), USER, TX_FEE_WEI);

            const record = await readRecord();
            assert.isTrue(record.ran, 'the hook ran');
            assert.equal(record.flow, 16, 'the hook ran inside the SEND_TRANSFER flow');
            assert.equal(record.succeeded, '0', 'no re-entry succeeded (bit i = call i)');
            assert.equal(await exportedTransfers(), before + 1, 'only the outer deposit was exported');
            assert.equal((await tokenIndex(HOSTILE)).toString(), String(COIN));
            assert.equal(BN(await hostile.balanceOf(delegator.address)).toString(), ONE_TOKEN);
            assert.equal((await claimable(FLOW_KEY)).toString(), '0', 'flow cleared');
        });

        it('control: the re-entered sendTransfer is valid on its own', async () => {
            const before = await exportedTransfers();
            await web3.eth.sendTransaction({ from: USER, to: delegator.address, data: calls.sendTransfer.data,
                value: calls.sendTransfer.value, gas: 15000000 });
            assert.equal(await exportedTransfers(), before + 1);
        });

        it('payout: during transfer (EXECUTE_IMPORT flow) every re-entry is refused, and the rest of the batch is paid', async () => {
            // The payout gets 100,000 gas: the token builds its three calls in code (payOutImport and vote routes,
            // and a direct payOutImport), and PAYEE already holds 1 wei so the transfer's balance write is cheap.
            await hostile.transfer(PAYEE, 1, { from: USER });
            await hostile.armPayout(await delegator.contracts(IMPORTS_SLOT));
            const payee2Before = BN(await web3.eth.getBalance(PAYEE2));
            const txid = await submitImport([
                payout({ currencyI: HOSTILE_I, amount: COIN, to: PAYEE }),
                payout({ amount: COIN, to: PAYEE2 }),
            ]);
            await release(txid);

            const record = await readRecord();
            assert.isTrue(record.ran, 'the hook ran');
            assert.equal(record.flow, 2, 'the hook ran inside the EXECUTE_IMPORT flow');
            assert.equal(record.succeeded, '0', 'no re-entry succeeded (bit i = call i)');
            assert.equal(BN(await hostile.balanceOf(PAYEE)).toString(), BN(ONE_TOKEN).addn(1).toString(), 'token payout made');
            assert.equal((await tokenIndex(HOSTILE)).toString(), '0', 'token ledger debited');
            assert.equal(BN(await web3.eth.getBalance(PAYEE2)).sub(payee2Before).toString(), BN(COIN).mul(SATS_TO_WEI).toString(),
                'the next payout still runs in its flow');
            assert.equal((await claimable(FLOW_KEY)).toString(), '0', 'flow cleared');
        });
    });

    describe('Refund claims and fee payouts still work through their flows', () => {
        isolate();

        it('claimRefund pays a DEST_ETH refund key on Ethereum (CLAIM_REFUND flow)', async () => {
            const txid = await submitImport([payout({ amount: 2 * COIN, to: rejecter.address, aux: [[DEST_ETH, PAYEE2]] })],
                { launched: true });
            await release(txid);
            const key = destKey(DEST_ETH, PAYEE2);
            assert.equal((await refund(key, VETH)).toString(), String(2 * COIN));
            const before = BN(await web3.eth.getBalance(PAYEE2));
            await send(web3Delegator.methods.claimRefund(key, VETH), USER);
            assert.equal(BN(await web3.eth.getBalance(PAYEE2)).sub(before).toString(), BN(2 * COIN).mul(SATS_TO_WEI).toString());
            assert.equal((await refund(key, VETH)).toString(), '0');
        });

        it('sendfees exports an ID proposer\'s fees back to Verus (SEND_FEES flow)', async () => {
            const idProposer = destKey(DEST_ID, '0x' + '7a'.repeat(20));
            const txid = await submitImport([payout({ amount: COIN, to: PAYEE, fees: 40000000 })], { proposer: idProposer, launched: true });
            await release(txid);
            const credited = await claimable(claimKey(idProposer));
            assert.isTrue(credited.gtn(600000), 'ID proposer credited above the payout threshold');
            await send(web3Delegator.methods.sendfees(claimKey(idProposer), '0x' + '00'.repeat(32)), USER);
            assert.equal((await claimable(claimKey(idProposer))).toString(), '0', 'fees exported');
        });
    });
});
