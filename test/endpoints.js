/**
 * endpoints.js
 *
 * One test (or more) for every external endpoint of the Delegator and for every route reachable
 * through Delegator.setVerusData. Sends real ETH, DAI and MKR into the bridge through sendTransfer /
 * sendTransferDirect, like testnet/send-transfers.js does.
 *
 * The bridge is in its pre-launch state on the dev network (bridgeConverterActive == false), so the
 * launch-only endpoints (claimfees, sendfees, claimRefund, burnFees) are tested for their guard.
 * Endpoints that need a Verus proof or notary quorum (submitImports, setLatestData success path,
 * upgradeContracts success path) have their success path in deployed.js / pendingImports.lifecycle.js
 * and are tested here for their guards. The meta tests at the bottom fail when an endpoint is added
 * without being listed here.
 *
 * Run:  ganache-cli -d, then  truffle test test/endpoints.js --to 2
 */

'use strict';

const VerusDelegator    = artifacts.require('../contracts/Main/Delegator.sol');
const Token             = artifacts.require('Token');
const MockSeedImport    = artifacts.require('MockSeedImport');
const verusDelegatorAbi = require('../build/contracts/Delegator.json');
const pendingImportsAbi = require('../build/contracts/PendingImports.json').abi;
const reservetransfer   = require('./reservetransfer.ts');
const { getNotarizerIDS } = require('../migrations/setup.js');

const abi = web3.eth.abi;
const BN  = web3.utils.toBN;

const VETH = '0x67460C2f56774eD27EeB8685f29f6CEC0B090B00';
const VRSC = '0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d';
const ZERO = '0x0000000000000000000000000000000000000000';
const DAI_IADDRESS = '0xcce5d18f305474f1e0e0ec1c507d8c85e7315fdf';
const MKR_IADDRESS = '0x005005b2b10a897fed36fbd71c878213a7a169bf';

const TX_FEE_WEI = '3000000000000000';     // 0.003 ETH, VerusConstants.transactionFee
const VRSC_FEE_SATS = 2000000;             // VerusConstants.verusTransactionFee
const SATS_TO_WEI = BN('10000000000');
const ONE_COIN_SATS = 100000000;

const DEST = '0x9bB2772Aa50ec96ce1305D926B9CC29b7c402bAD';

// Every Delegator function, and the test group below that covers it. See the meta tests.
const COVERED_DELEGATOR_FUNCTIONS = [
    'sendTransfer', 'sendTransferDirect', 'submitImports', 'getReadyExportsByRange', 'setLatestData',
    'launchContractTokens', 'getTokenList', 'checkImport', 'claimfees', 'claimRefund', 'sendfees',
    'getProof', 'getProofCosts', 'upgradeContracts', 'replacecontract', 'revokeWithMainAddress',
    'revokeWithMultiSig', 'recoverWithRecoveryAddress', 'recoverWithMultiSig', 'getVoteCount',
    'burnFees', 'setVerusData',
];
// Public state getters on the Delegator, read in 'public getters'.
const COVERED_GETTERS = [
    '_readyExports', 'exportHeights', 'processedTxids', 'verusToERC20mapping', 'lastImportInfo', 'tokenList',
    'lastTxIdImport', 'cceLastStartHeight', 'cceLastEndHeight', 'bridgeConverterActive', 'storageGlobal',
    'claimableFees', 'refunds', 'contracts', 'rollingUpgradeVotes', 'rollingVoteIndex', 'saltsUsed',
    'notaryAddressMapping', 'notaries', 'bestForks', 'owner',
];
// Every setVerusData route registered by UpgradeManager.initialize.
const COVERED_ROUTES = [
    'getPendingImports', 'getPendingImportCount', 'approveOrRejectAcceptedImport', 'executeTimedOutImport',
    'isBridgePaused', 'getNotaryIAddress', 'submitUnhaltVote',
];

const rpc = (method, params = []) =>
    new Promise((resolve, reject) =>
        web3.currentProvider.send({ jsonrpc: '2.0', method, params, id: Date.now() },
            (err, res) => (err ? reject(err) : resolve(res))));

function findEvent(receipt, eventName) {
    const eventAbi = pendingImportsAbi.find(e => e.type === 'event' && e.name === eventName);
    const topic = web3.eth.abi.encodeEventSignature(eventAbi);
    const log = (receipt.logs || []).find(l => l.topics[0] === topic);
    return log ? web3.eth.abi.decodeLog(eventAbi.inputs, log.data, log.topics.slice(1)) : null;
}

contract('Delegator endpoints', async (accounts) => {

    const OWNER = accounts[0];
    const USER = accounts[5];
    const NOTARIES = [accounts[1], accounts[2], accounts[3]];
    let delegator;      // truffle instance
    let web3Delegator;  // raw web3 contract (receipts keep the logs of delegatecalled contracts)
    let dai;
    let mkr;
    let snapshotId;

    const isolate = () => {
        before(async () => { snapshotId = (await rpc('evm_snapshot')).result; });
        after(async () => { await rpc('evm_revert', [snapshotId]); });
    };

    const expectRevert = async (promise, message) => {
        try {
            await promise;
        } catch (e) {
            assert.include(e.message, 'revert', message);
            return e;
        }
        assert.fail('expected revert: ' + message);
    };

    // A prelaunch CReserveTransfer: VRSC is the fee and destination currency.
    const transferStruct = (currency, amountSats, overrides = {}) => Object.assign({
        version: 1,
        currencyvalue: { currency, amount: amountSats },
        flags: 1,
        feecurrencyid: VRSC,
        fees: VRSC_FEE_SATS,
        destination: { destinationtype: 2, destinationaddress: DEST },
        destcurrencyid: VRSC,
        destsystemid: ZERO,
        secondreserveid: ZERO,
    }, overrides);

    const tokenIndex = async (currency) => BN((await delegator.verusToERC20mapping(currency)).tokenIndex);
    const ethValueFor = (amountSats) => BN(amountSats).mul(SATS_TO_WEI).add(BN(TX_FEE_WEI));
    const send = (method, from, value = '0') => web3.eth.sendTransaction({
        from, to: delegator.address, data: method.encodeABI(), gas: 6000000, value,
    });

    before(async () => {
        delegator = await VerusDelegator.deployed();
        web3Delegator = new web3.eth.Contract(verusDelegatorAbi.abi, delegator.address);

        const tokens = await delegator.getTokenList.call(0, 0);
        const byAddress = (iaddress) => tokens.find(t => t.iaddress.toLowerCase() === iaddress.toLowerCase());
        dai = await Token.at(byAddress(DAI_IADDRESS).erc20ContractAddress);
        mkr = await Token.at(byAddress(MKR_IADDRESS).erc20ContractAddress);

        // Deployer holds the minted DAI and MKR; give the test user some, as a wallet would have.
        const funding = web3.utils.toWei('1000', 'ether');
        await dai.transfer(USER, funding, { from: OWNER });
        await mkr.transfer(USER, funding, { from: OWNER });
        for (const n of NOTARIES) {
            await web3.eth.sendTransaction({ from: OWNER, to: n, value: web3.utils.toWei('2', 'ether'), gas: 21000 });
        }
    });

    describe('receive()', () => {
        isolate();

        it('accepts plain ETH without crediting tokenIndex', async () => {
            const before = await web3.eth.getBalance(delegator.address);
            const index = await tokenIndex(VETH);
            await web3.eth.sendTransaction({ from: USER, to: delegator.address, value: web3.utils.toWei('1', 'ether') });
            assert.equal(BN(await web3.eth.getBalance(delegator.address)).sub(BN(before)).toString(), web3.utils.toWei('1', 'ether'));
            assert.equal((await tokenIndex(VETH)).toString(), index.toString(), 'unsolicited ETH is outside the accounting');
        });
    });

    describe('public getters', () => {
        it('every getter listed in COVERED_GETTERS exists on the ABI and is callable', async () => {
            const abiNames = verusDelegatorAbi.abi.filter(f => f.type === 'function' && f.stateMutability === 'view').map(f => f.name);
            for (const name of COVERED_GETTERS) {
                assert.include(abiNames, name, name + ' missing from the Delegator ABI');
            }
        });

        it('bridge starts in the pre-launch state', async () => {
            assert.isFalse(await delegator.bridgeConverterActive());
            assert.equal((await delegator.rollingVoteIndex()).toString(), '200');
            assert.equal((await delegator.cceLastStartHeight()).toString(), '0');
            assert.equal((await delegator.lastTxIdImport()).length, 66);
        });

        it('notaries / notaryAddressMapping reflect the deployment', async () => {
            const [ids, signers] = getNotarizerIDS('development');
            assert.equal(ids.length, 3);
            for (let i = 0; i < ids.length; i++) {
                assert.equal((await delegator.notaries(i)).toLowerCase(), ids[i].toLowerCase());
                const mapping = await delegator.notaryAddressMapping(ids[i]);
                assert.equal(mapping.main.toLowerCase(), signers[i].toLowerCase());
                assert.equal(mapping.state.toString(), '1', 'NOTARY_VALID');
            }
            await expectRevert(delegator.notaries(3), 'notaries(3) is out of bounds');
        });

        it('contracts[] has the 13 delegated slots, rollingUpgradeVotes starts empty', async () => {
            for (let i = 0; i < 13; i++) {
                assert.notEqual(await delegator.contracts(i), ZERO, 'contracts(' + i + ')');
            }
            await expectRevert(delegator.contracts(13), 'contracts(13) is out of bounds');
            assert.equal(await delegator.rollingUpgradeVotes(0), ZERO);
        });

        it('verusToERC20mapping / tokenList / mapping owner and misc state', async () => {
            const veth = await delegator.verusToERC20mapping(VETH);
            assert.isAbove(Number(veth.flags), 0, 'VETH is registered');
            assert.notEqual(await delegator.tokenList(0), ZERO, 'tokenList(0) is the VerusNFT contract');
            assert.equal(await delegator.owner(), ZERO);
            assert.isFalse(await delegator.saltsUsed(web3.utils.randomHex(32)));
            assert.isFalse(await delegator.processedTxids(web3.utils.randomHex(32)));
            assert.equal((await delegator.claimableFees(web3.utils.randomHex(32))).toString(), '0');
            assert.equal((await delegator.refunds(web3.utils.randomHex(32), DAI_IADDRESS)).toString(), '0');
            assert.equal((await delegator.lastImportInfo(web3.utils.randomHex(32))).height.toString(), '0');
            assert.equal((await delegator.exportHeights(0)).toString(), '0');
            assert.equal((await delegator.cceLastEndHeight()).toString(), '0', 'no export yet');
        });

        it('storageGlobal returns the registered route index, empty for unknown keys', async () => {
            const indexData = await delegator.storageGlobal(web3.utils.keccak256('getPendingImports'));
            assert.equal(abi.decodeParameter('uint256', indexData).toString(), '11');
            const empty = await delegator.storageGlobal(web3.utils.keccak256('no.such.key'));
            assert.isTrue(empty === null || empty === '0x');
        });

        it('bestForks and _readyExports are empty on a fresh deployment', async () => {
            await expectRevert(delegator.bestForks(0), 'no notarization has been accepted yet');
            const ready = await delegator._readyExports(1);
            assert.equal(ready.transfers === undefined || ready.transfers.length === 0, true);
        });
    });

    describe('getTokenList', () => {
        it('returns all six registered currencies', async () => {
            const list = await delegator.getTokenList.call(0, 0);
            assert.equal(list.length, 6);
            assert.include(list.map(t => t.iaddress.toLowerCase()), VETH.toLowerCase());
            const names = list.map(t => t.name);
            assert.deepEqual(names, ['VerusNFT', 'VRSCTEST', 'Bridge.vETH', 'ETH (Testnet)', 'DAI (Testnet)', 'Maker (Testnet)']);
            assert.equal(list[3].ticker, 'ETH');
        });

        it('honours the start and end range', async () => {
            const list = await delegator.getTokenList.call(1, 3);
            assert.equal(list.length, 3);
            const single = await delegator.getTokenList.call(2, 2);
            assert.equal(single.length, 6 - 2, 'an end <= start returns through the end of the list');
        });

        it('an out-of-range start falls back to the first token', async () => {
            const list = await delegator.getTokenList.call(100, 0);
            assert.equal(list.length, 6);
        });
    });

    describe('sendTransfer: ETH', () => {
        isolate();

        it('credits tokenIndex and records an export', async () => {
            const index = await tokenIndex(VETH);
            const balance = BN(await web3.eth.getBalance(delegator.address));
            const value = ethValueFor(ONE_COIN_SATS);

            const receipt = await web3Delegator.methods.sendTransfer(transferStruct(VETH, ONE_COIN_SATS))
                .send({ from: USER, gas: 6000000, value: value.toString() });

            assert.equal(BN(await web3.eth.getBalance(delegator.address)).sub(balance).toString(), value.toString());
            assert.equal((await tokenIndex(VETH)).sub(index).toString(), value.div(SATS_TO_WEI).toString());

            const exports = await delegator.getReadyExportsByRange.call(0, receipt.blockNumber + 10);
            assert.isAbove(exports.length, 0);
            const last = exports[exports.length - 1];
            assert.equal(last.transfers[last.transfers.length - 1].currencyvalue.currency.toLowerCase(), VETH.toLowerCase());
            assert.equal(last.transfers[last.transfers.length - 1].currencyvalue.amount.toString(), String(ONE_COIN_SATS));
        });

        it('rejects msg.value that does not match amount + fee', async () => {
            await expectRevert(web3Delegator.methods.sendTransfer(transferStruct(VETH, ONE_COIN_SATS))
                .send({ from: USER, gas: 6000000, value: TX_FEE_WEI }), 'value short');
            await expectRevert(web3Delegator.methods.sendTransfer(transferStruct(VETH, ONE_COIN_SATS))
                .send({ from: USER, gas: 6000000, value: ethValueFor(ONE_COIN_SATS).add(BN(1)).toString() }), 'value too high');
        });

        it('rejects an invalid VRSC fee, fee currency, flags, version and destination', async () => {
            const value = ethValueFor(ONE_COIN_SATS).toString();
            const bad = {
                'fee': { fees: VRSC_FEE_SATS + 1 },
                'fee currency': { feecurrencyid: VETH },
                'flags': { flags: 0 },
                'invalid flag bit': { flags: 1 | 0x8000 },
                'version': { version: 2 },
                'zero destination': { destination: { destinationtype: 2, destinationaddress: ZERO } },
                'dest system': { destsystemid: VRSC },
            };
            for (const [name, override] of Object.entries(bad)) {
                await expectRevert(web3Delegator.methods.sendTransfer(transferStruct(VETH, ONE_COIN_SATS, override))
                    .send({ from: USER, gas: 6000000, value }), name);
            }
        });
    });

    describe('sendTransferDirect: ETH', () => {
        isolate();

        it('accepts a serialized reserve transfer and credits tokenIndex', async () => {
            const index = await tokenIndex(VETH);
            const value = web3.utils.toWei('1.003', 'ether');
            const serialized = `0x${reservetransfer.prelaunchfundETH.toBuffer().toString('hex')}`;

            const receipt = await web3Delegator.methods.sendTransferDirect(serialized).send({ from: USER, gas: 6000000, value });

            assert.equal((await tokenIndex(VETH)).sub(index).toString(), BN(value).div(SATS_TO_WEI).toString());
            const exports = await delegator.getReadyExportsByRange.call(0, receipt.blockNumber + 10);
            assert.equal(exports[exports.length - 1].endHeight.toString(), String(receipt.blockNumber));
        });

        it('reverts on garbage and on truncated input', async () => {
            await expectRevert(web3Delegator.methods.sendTransferDirect('0x').send({ from: USER, gas: 6000000 }), 'empty');
            await expectRevert(web3Delegator.methods.sendTransferDirect('0xdeadbeef').send({ from: USER, gas: 6000000 }), 'garbage');
            const serialized = reservetransfer.prelaunchfundETH.toBuffer().toString('hex');
            await expectRevert(web3Delegator.methods.sendTransferDirect('0x' + serialized.slice(0, 40))
                .send({ from: USER, gas: 6000000, value: web3.utils.toWei('1.003', 'ether') }), 'truncated');
        });
    });

    describe('sendTransfer: DAI and MKR', () => {
        isolate();

        for (const [name, getToken] of [['DAI', () => dai], ['MKR', () => mkr]]) {
            const iaddress = name === 'DAI' ? DAI_IADDRESS : MKR_IADDRESS;
            const amountSats = 10 * ONE_COIN_SATS;
            const amountWei = BN(web3.utils.toWei('10', 'ether'));

            it(name + ': pulls the tokens, credits tokenIndex, charges the ETH fee and records the export', async () => {
                const token = getToken();
                const userBefore = BN(await token.balanceOf(USER));
                const index = await tokenIndex(iaddress);
                const ethBefore = BN(await web3.eth.getBalance(delegator.address));

                await token.approve(delegator.address, amountWei, { from: USER });
                const receipt = await web3Delegator.methods.sendTransfer(transferStruct(iaddress, amountSats))
                    .send({ from: USER, gas: 6000000, value: TX_FEE_WEI });

                assert.equal(userBefore.sub(BN(await token.balanceOf(USER))).toString(), amountWei.toString());
                assert.equal((await tokenIndex(iaddress)).sub(index).toString(), String(amountSats));
                assert.equal(BN(await web3.eth.getBalance(delegator.address)).sub(ethBefore).toString(), TX_FEE_WEI);
                assert.equal((await token.allowance(USER, delegator.address)).toString(), '0', 'allowance fully consumed');

                const exports = await delegator.getReadyExportsByRange.call(0, receipt.blockNumber + 10);
                const transfers = exports[exports.length - 1].transfers;
                assert.equal(transfers[transfers.length - 1].currencyvalue.currency.toLowerCase(), iaddress.toLowerCase());
            });

            it(name + ': reverts without an allowance', async () => {
                await expectRevert(web3Delegator.methods.sendTransfer(transferStruct(iaddress, amountSats))
                    .send({ from: USER, gas: 6000000, value: TX_FEE_WEI }), 'no allowance');
            });

            it(name + ': reverts when the allowance is smaller than the amount', async () => {
                const token = getToken();
                await token.approve(delegator.address, amountWei.subn(1), { from: USER });
                await expectRevert(web3Delegator.methods.sendTransfer(transferStruct(iaddress, amountSats))
                    .send({ from: USER, gas: 6000000, value: TX_FEE_WEI }), 'allowance too small');
                await token.approve(delegator.address, 0, { from: USER });
            });

            it(name + ': reverts when the ETH fee is missing or wrong', async () => {
                const token = getToken();
                await token.approve(delegator.address, amountWei, { from: USER });
                await expectRevert(web3Delegator.methods.sendTransfer(transferStruct(iaddress, amountSats))
                    .send({ from: USER, gas: 6000000, value: '0' }), 'no ETH fee');
                await expectRevert(web3Delegator.methods.sendTransfer(transferStruct(iaddress, amountSats))
                    .send({ from: USER, gas: 6000000, value: BN(TX_FEE_WEI).addn(1).toString() }), 'ETH fee too high');
                await token.approve(delegator.address, 0, { from: USER });
            });

            it(name + ': reverts when the sender holds fewer tokens than approved', async () => {
                const token = getToken();
                const poor = accounts[8];
                await token.approve(delegator.address, amountWei, { from: poor });
                await expectRevert(web3Delegator.methods.sendTransfer(transferStruct(iaddress, amountSats))
                    .send({ from: poor, gas: 6000000, value: TX_FEE_WEI }), 'insufficient balance');
            });
        }

        it('an unregistered token cannot be sent', async () => {
            await expectRevert(web3Delegator.methods.sendTransfer(transferStruct('0x1234567890123456789012345678901234567890', ONE_COIN_SATS))
                .send({ from: USER, gas: 6000000, value: TX_FEE_WEI }), 'unregistered currency');
        });
    });

    describe('getReadyExportsByRange', () => {
        isolate();

        it('is empty before any transfer', async () => {
            const exports = await delegator.getReadyExportsByRange.call(0, 1000000);
            assert.equal(exports.length, 0);
        });

        it('returns the exports inside the range and hash-links consecutive exports', async () => {
            const first = await web3Delegator.methods.sendTransfer(transferStruct(VETH, ONE_COIN_SATS))
                .send({ from: USER, gas: 6000000, value: ethValueFor(ONE_COIN_SATS).toString() });
            // more than 10 blocks later a new export (CCE) starts
            for (let i = 0; i < 12; i++) await rpc('evm_mine');
            const second = await web3Delegator.methods.sendTransfer(transferStruct(VETH, ONE_COIN_SATS))
                .send({ from: USER, gas: 6000000, value: ethValueFor(ONE_COIN_SATS).toString() });

            const all = await delegator.getReadyExportsByRange.call(0, second.blockNumber + 10);
            assert.equal(all.length, 2);
            assert.equal(all[1].prevExportHash, all[0].exportHash, 'exports are hash linked');
            assert.equal(all[0].endHeight.toString(), String(first.blockNumber));
            assert.equal(all[1].endHeight.toString(), String(second.blockNumber));

            // the end of the range is exclusive of an export that ends on it
            assert.equal((await delegator.getReadyExportsByRange.call(0, first.blockNumber)).length, 0);
            const onlyFirst = await delegator.getReadyExportsByRange.call(0, first.blockNumber + 1);
            assert.equal(onlyFirst.length, 1);
            assert.equal(onlyFirst[0].exportHash, all[0].exportHash);
        });
    });

    describe('setLatestData (notarizations)', () => {
        it('reverts for malformed notarization data (success path: deployed.js)', async () => {
            await expectRevert(web3Delegator.methods.setLatestData('0x', web3.utils.randomHex(32), 0, '0x')
                .send({ from: NOTARIES[0], gas: 6000000 }), 'empty');
            await expectRevert(web3Delegator.methods.setLatestData('0xdeadbeef', web3.utils.randomHex(32), 0, '0x')
                .send({ from: NOTARIES[0], gas: 6000000 }), 'garbage');
        });
    });

    describe('submitImports', () => {
        it('reverts for an import without a valid proof (success path: pendingImports.lifecycle.js)', async () => {
            const empty = {
                partialtransactionproof: { version: 1, typeC: 1, txproof: [], components: [] },
                serializedTransfers: '0x',
            };
            await expectRevert(web3Delegator.methods.submitImports(empty).send({ from: OWNER, gas: 6000000 }), 'no proof');
        });
    });

    describe('checkImport', () => {
        it('is false for an unknown txid', async () => {
            assert.isFalse(await delegator.checkImport(web3.utils.randomHex(32)));
        });
    });

    describe('launch-only fee endpoints (claimfees, sendfees, claimRefund, burnFees)', () => {
        it('claimfees reverts before the bridge converter is active', async () => {
            await expectRevert(delegator.claimfees({ from: USER }), 'claimfees');
        });

        it('sendfees reverts before the bridge converter is active', async () => {
            await expectRevert(delegator.sendfees(web3.utils.randomHex(32), web3.utils.randomHex(32), { from: USER }), 'sendfees');
        });

        it('claimRefund reverts before the bridge converter is active and with nothing to refund', async () => {
            await expectRevert(delegator.claimRefund('0x' + '11'.repeat(21), DAI_IADDRESS, { from: USER }), 'claimRefund');
            await expectRevert(delegator.claimRefund(0, VETH, { from: USER }), 'claimRefund zero address');
        });

        it('burnFees reverts before the bridge converter is active', async () => {
            const e = await expectRevert(delegator.burnFees('0x', { from: USER }), 'burnFees');
            assert.isString(e.message);
        });
    });

    describe('getProof / getProofCosts', () => {
        isolate();

        it('getProofCosts returns the three proof prices (0.01, 0.005, 0.0025 ETH)', async () => {
            const prices = ['0.01', '0.005', '0.0025'].map(p => web3.utils.toWei(p, 'ether'));
            for (let i = 0; i < 3; i++) {
                assert.equal((await delegator.getProofCosts.call(i)).toString(), prices[i], 'option ' + i);
            }
            await expectRevert(delegator.getProofCosts.call(3), 'only options 0-2 have a price');
        });

        it('getProof reverts when the fee is wrong, or when no notarization exists yet', async () => {
            await expectRevert(delegator.getProof(0, { from: USER, value: '0' }), 'no fee');
            await expectRevert(delegator.getProof(0, { from: USER, value: web3.utils.toWei('0.011', 'ether') }), 'fee too high');
            await expectRevert(delegator.getProof(0, { from: USER, value: web3.utils.toWei('0.01', 'ether') }), 'no notarization to prove yet');
        });
    });

    describe('upgradeContracts / getVoteCount', () => {
        const upgradeData = (contracts, salt) => abi.encodeParameter(
            'tuple(uint8,bytes32,bytes32,address[],uint8,bytes32,address,uint32)',
            [0, '0x' + '00'.repeat(32), '0x' + '00'.repeat(32), contracts, 1, salt, ZERO, 0]);

        it('getVoteCount is zero for a hash nobody voted for', async () => {
            assert.equal((await delegator.getVoteCount.call(web3.utils.randomHex(20))).toString(), '0');
            assert.equal((await delegator.getVoteCount.call(ZERO)).toString(), '50', 'the empty vote slots all match the zero hash');
        });

        it('upgradeContracts does not accept ETH', async () => {
            const contracts = [];
            for (let i = 0; i < 13; i++) contracts.push(await delegator.contracts(i));
            await expectRevert(delegator.upgradeContracts(upgradeData(contracts, web3.utils.randomHex(32)),
                { from: NOTARIES[0], value: 1 }), 'ETH sent');
        });

        it('upgradeContracts rejects the wrong contract count and a hash without enough votes', async () => {
            await expectRevert(delegator.upgradeContracts(upgradeData([ZERO], web3.utils.randomHex(32)), { from: NOTARIES[0] }), 'wrong length');
            const contracts = [];
            for (let i = 0; i < 13; i++) contracts.push(await delegator.contracts(i));
            await expectRevert(delegator.upgradeContracts(upgradeData(contracts, web3.utils.randomHex(32)), { from: NOTARIES[0] }), 'no votes');
            await expectRevert(delegator.upgradeContracts('0x', { from: NOTARIES[0] }), 'empty');
        });
    });

    describe('replacecontract / launchContractTokens (owner only)', () => {
        isolate();

        it('replacecontract is owner only', async () => {
            await expectRevert(delegator.replacecontract(await delegator.contracts(2), 2, { from: USER }), 'non owner');
        });

        it('replacecontract re-registers a slot and re-runs its initialize()', async () => {
            const original = await delegator.contracts(2);
            await delegator.replacecontract(original, 2, { from: OWNER, gas: 6000000 });
            assert.equal(await delegator.contracts(2), original);
            const mock = await MockSeedImport.new();           // has initialize(); swapped in and back
            await delegator.replacecontract(mock.address, 12, { from: OWNER, gas: 6000000 });
            assert.equal(await delegator.contracts(12), mock.address);
        });

        it('replacecontract reverts when the new contract\'s initialize() reverts', async () => {
            const reverting = await Token.new('X', 'X');       // no initialize(): the delegatecall hits the ERC20 fallback and reverts
            await expectRevert(delegator.replacecontract(reverting.address, 2, { from: OWNER, gas: 6000000 }), 'initialize reverts');
        });

        it('launchContractTokens is owner only and only before tokens exist', async () => {
            await expectRevert(delegator.launchContractTokens('0x', { from: USER }), 'non owner');
            await expectRevert(delegator.launchContractTokens('0x', { from: OWNER, gas: 6000000 }), 'tokens already launched');
        });

        it('replacecontract(_, 100) renounces ownership for good', async () => {
            await delegator.replacecontract(ZERO, 100, { from: OWNER });
            await expectRevert(delegator.replacecontract(await delegator.contracts(2), 2, { from: OWNER }), 'owner renounced');
        });
    });

    describe('revoke / recover endpoints', () => {
        isolate();

        const state = async (index) => (await delegator.notaryAddressMapping(await delegator.notaries(index))).state.toString();

        it('revokeWithMainAddress revokes the calling notary only', async () => {
            await expectRevert(send(web3Delegator.methods.revokeWithMainAddress('0x'), USER), 'non-notary');
            await send(web3Delegator.methods.revokeWithMainAddress('0x'), NOTARIES[0]);
            assert.equal(await state(0), '2', 'NOTARY_REVOKED');
            assert.equal(await state(1), '1');
        });

        it('revokeWithMultiSig rejects malformed / unsigned data', async () => {
            await expectRevert(send(web3Delegator.methods.revokeWithMultiSig('0x'), USER), 'empty');
            const data = abi.encodeParameter('tuple(uint8,bytes32,bytes32,address[],uint8,bytes32,address,uint32)',
                [0, '0x' + '00'.repeat(32), '0x' + '00'.repeat(32), [], 0, web3.utils.randomHex(32), ZERO, 0]);
            await expectRevert(send(web3Delegator.methods.revokeWithMultiSig(data), USER), 'no signatures');
        });

        it('recoverWithRecoveryAddress rejects data that is not signed by the recovery key', async () => {
            await expectRevert(send(web3Delegator.methods.recoverWithRecoveryAddress('0x'), USER), 'empty');
            const data = abi.encodeParameter('tuple(uint8,bytes32,bytes32,address[],uint8,bytes32,address,uint32)',
                [27, '0x' + '11'.repeat(32), '0x' + '22'.repeat(32), [NOTARIES[0], NOTARIES[0]], 3, web3.utils.randomHex(32), ZERO, 0]);
            const before = await state(0);
            await expectRevert(send(web3Delegator.methods.recoverWithRecoveryAddress(data), USER), 'bad signature');
            assert.equal(await state(0), before, 'a rejected call changes no notary state');
        });

        it('recoverWithMultiSig rejects malformed / unsigned data', async () => {
            await expectRevert(send(web3Delegator.methods.recoverWithMultiSig('0x'), USER), 'empty');
            const data = abi.encodeParameter('tuple(uint8,bytes32,bytes32,address[],uint8,bytes32,address,uint32)',
                [0, '0x' + '00'.repeat(32), '0x' + '00'.repeat(32), [], 0, web3.utils.randomHex(32), ZERO, 0]);
            await expectRevert(send(web3Delegator.methods.recoverWithMultiSig(data), USER), 'no signatures');
        });
    });

    describe('setVerusData routes', () => {
        isolate();

        const route = (name, data, from, value = '0') => send(web3Delegator.methods.setVerusData(data, name), from, value);
        const call = (name, data, from) => web3Delegator.methods.setVerusData(data, name).call({ from });
        const txid = web3.utils.randomHex(32);

        it('an unregistered route reverts', async () => {
            await expectRevert(route('noSuchRoute', '0x', NOTARIES[0]), 'unknown route');
            await expectRevert(route('submitHaltVote', abi.encodeParameter('bool', true), NOTARIES[0]), 'removed route');
            await expectRevert(route('', '0x', NOTARIES[0]), 'empty route');
        });

        it('all documented routes are registered to PendingImports (slot 11)', async () => {
            for (const name of COVERED_ROUTES) {
                const registered = await delegator.storageGlobal(web3.utils.keccak256(name));
                assert.equal(abi.decodeParameter('uint256', registered).toString(), '11', name);
            }
        });

        it('getPendingImportCount / getPendingImports / isBridgePaused / getNotaryIAddress do not revert', async () => {
            await call('getPendingImportCount', '0x', USER);
            await call('getPendingImports', abi.encodeParameters(['uint256', 'uint256'], [0, 10]), USER);
            await call('isBridgePaused', '0x', USER);
            await call('getNotaryIAddress', '0x', NOTARIES[0]);
        });

        it('getNotaryIAddress does not revert for a non notary (it resolves to the zero address)', async () => {
            await call('getNotaryIAddress', '0x', USER);
        });

        it('approveOrRejectAcceptedImport reverts for non-notaries and unknown imports, both decisions', async () => {
            for (const decision of [true, false]) {
                const data = abi.encodeParameters(['bytes32', 'bool'], [txid, decision]);
                await expectRevert(route('approveOrRejectAcceptedImport', data, USER), 'non notary ' + decision);
                await expectRevert(route('approveOrRejectAcceptedImport', data, NOTARIES[0]), 'unknown import ' + decision);
            }
            await expectRevert(route('approveOrRejectAcceptedImport', '0x', NOTARIES[0]), 'empty payload');
        });

        it('executeTimedOutImport reverts for non-notaries and unknown imports', async () => {
            const data = abi.encodeParameter('bytes32', txid);
            await expectRevert(route('executeTimedOutImport', data, USER), 'non notary');
            await expectRevert(route('executeTimedOutImport', data, NOTARIES[0]), 'unknown import');
        });

        it('submitUnhaltVote reverts while the bridge is not halted', async () => {
            await expectRevert(route('submitUnhaltVote', abi.encodeParameter('bool', true), NOTARIES[0]), 'not halted');
        });

        it('a temporary halt (all notaries revoked) closes sendTransfer and sendTransferDirect (full halt matrix: bridgeHalt.js)', async () => {
            for (const n of NOTARIES) await send(web3Delegator.methods.revokeWithMainAddress('0x'), n);
            assert.equal((await delegator.claimableFees('0x000000000000000000000000b024b1e290c833d9c5703ef6184a7c84e7ddd335')).toString(), '6');
            await expectRevert(web3Delegator.methods.sendTransfer(transferStruct(VETH, ONE_COIN_SATS))
                .send({ from: USER, gas: 6000000, value: ethValueFor(ONE_COIN_SATS).toString() }), 'sendTransfer while halted');
            await expectRevert(web3Delegator.methods.sendTransferDirect('0x').send({ from: USER, gas: 6000000 }), 'sendTransferDirect while halted');
        });
    });

    describe('coverage meta tests', () => {
        it('every external Delegator function has a test group in COVERED_DELEGATOR_FUNCTIONS', () => {
            const functions = verusDelegatorAbi.abi
                .filter(f => f.type === 'function' && f.stateMutability !== 'view' && f.stateMutability !== 'pure')
                .map(f => f.name)
                // inherited ERC1155Holder / ERC721Holder callbacks are not bridge endpoints
                .filter(name => !/^on(ERC721|ERC1155|ERC1155Batch)Received$/.test(name));
            const missing = functions.filter(name => !COVERED_DELEGATOR_FUNCTIONS.includes(name));
            assert.deepEqual(missing, [], 'Delegator endpoints without a test: ' + missing.join(', '));
        });

        it('COVERED_DELEGATOR_FUNCTIONS has no stale entries', () => {
            const names = verusDelegatorAbi.abi.filter(f => f.type === 'function').map(f => f.name);
            const stale = COVERED_DELEGATOR_FUNCTIONS.filter(name => !names.includes(name));
            assert.deepEqual(stale, [], 'covered but no longer on the ABI: ' + stale.join(', '));
        });

        it('every public getter of the Delegator is in COVERED_GETTERS', () => {
            const getters = verusDelegatorAbi.abi
                .filter(f => f.type === 'function' && (f.stateMutability === 'view' || f.stateMutability === 'pure'))
                .map(f => f.name)
                .filter(name => !['checkImport', 'supportsInterface'].includes(name));
            const missing = getters.filter(name => !COVERED_GETTERS.includes(name));
            assert.deepEqual(missing, [], 'getters without a test: ' + missing.join(', '));
        });

        it('every setVerusData route of PendingImports is in COVERED_ROUTES', () => {
            const routes = pendingImportsAbi
                .filter(f => f.type === 'function' && f.inputs.length === 1 && f.inputs[0].type === 'bytes')
                .map(f => f.name);
            const missing = routes.filter(name => !COVERED_ROUTES.includes(name));
            assert.deepEqual(missing, [], 'routes without a test: ' + missing.join(', '));
        });

        it('the ERC721 / ERC1155 receiver callbacks are present so NFTs can be deposited', async () => {
            const names = verusDelegatorAbi.abi.filter(f => f.type === 'function').map(f => f.name);
            for (const name of ['onERC721Received', 'onERC1155Received', 'onERC1155BatchReceived', 'supportsInterface']) {
                assert.include(names, name);
            }
            assert.isTrue(await delegator.supportsInterface('0x01ffc9a7'), 'ERC165');
        });
    });
});
