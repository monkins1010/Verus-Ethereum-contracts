'use strict';
/**
 * send-transfers.js
 *
 * Connects to the running Ganache testnet and sends three example
 * reserve transfers to the deployed Verus Bridge Delegator contract:
 *
 *   1. 1 vETH  – via sendTransferDirect  (serialised ReserveTransfer bytes)
 *   2. 10 DAI  – via sendTransfer        (ABI-encoded CReserveTransfer struct)
 *   3. 1  MKR  – via sendTransfer        (ABI-encoded CReserveTransfer struct)
 *
 * Requires the Ganache testnet to be running and contracts to be deployed:
 *   node testnet/start-ganache.js
 *
 * Usage:
 *   node testnet/send-transfers.js
 */

const Web3 = require('web3');
const { CurrencyValueMap, ReserveTransfer, TransferDestination } = require('verus-typescript-primitives');
const BN   = require('bn.js');
const path = require('path');
const fs   = require('fs');

// ─── Config ───────────────────────────────────────────────────────────────────
const STATE_FILE = path.join(__dirname, '.testnet-state.json');
const ROOT       = path.resolve(__dirname, '..');
const DEFAULT_RPC = 'http://127.0.0.1:8545';

// ─── Verus testnet currency iaddresses (hex / uint160) ────────────────────────
//     These match setup.js  id.testnet.*
const TESTNET = {
    VETH  : '0x67460C2f56774eD27EeB8685f29f6CEC0B090B00',
    VRSC  : '0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d',
    BRIDGE: '0xffEce948b8A38bBcC813411D2597f7f8485a0689',
    DAI   : '0xcce5d18f305474f1e0e0ec1c507d8c85e7315fdf',
    MKR   : '0x005005b2b10a897fed36fbd71c878213a7a169bf',
};

// ─── Verus base58 i-addresses used by ReserveTransfer (verus-typescript-primitives) ──
//     iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm  → testnet vETH
//     iJhCezBExJHvtyH3fGhNnt2NhU4Ztkf2yq  → testnet VRSC
const IADDR_VETH = 'iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm';
const IADDR_VRSC = 'iJhCezBExJHvtyH3fGhNnt2NhU4Ztkf2yq';

// ─── Transfer constants ───────────────────────────────────────────────────────
const VALID             = 1;
const DEST_PKH          = 2;
const TX_FEE_WEI        = '3000000000000000';   // 0.003 ETH (VerusConstants.transactionFee)
const VERUS_TX_FEE_SATS = 2000000;              // 0.02 VRSC (VerusConstants.verusTransactionFee, 8 dp)
const VETH_TX_FEE_SATS  = 300000;               // 0.003 vETH (VerusConstants.verusvETHTransactionFee, 8 dp)

// All test transfers go to this Ethereum destination address (20 bytes, no 0x)
const DEST_ADDR_HEX = '55f51a22c79018a00ced41e758560f5df7d4d35d';

// vETH amount: 1 ETH in Verus 8-decimal satoshis
const VETH_AMOUNT_SATS  = 100000000;
// ETH value to send: vETH amount (1 ETH) + fee (0.003 ETH)
const VETH_MSG_VALUE    = Web3.utils.toWei('1.003', 'ether');

// DAI amount: 10 DAI in Verus 8-decimal satoshis  (10 × 10^8)
const DAI_AMOUNT_SATS   = 1000000000;
// MKR amount:  1 MKR in Verus 8-decimal satoshis  ( 1 × 10^8)
const MKR_AMOUNT_SATS   =  100000000;

// ─── ReserveTransfer builder (prelaunch only, for sendTransferDirect) ─────────
function buildPrelaunchVethTransfer() {
    return new ReserveTransfer({
        values: new CurrencyValueMap({
            valueMap: new Map([
                [IADDR_VETH, new BN(VETH_AMOUNT_SATS, 10)]
            ]),
            multivalue: false,
        }),
        version    : new BN(1, 10),
        flags      : new BN(VALID, 10),
        feeCurrencyID : IADDR_VRSC,
        feeAmount     : new BN(VERUS_TX_FEE_SATS, 10),
        transferDestination: new TransferDestination({
            type            : new BN(DEST_PKH, 10),
            destinationBytes: Buffer.from(DEST_ADDR_HEX, 'hex'),
            fees            : new BN(0, 10),
        }),
        destCurrencyID: IADDR_VRSC,
    });
}

// ─── CReserveTransfer struct builder (for sendTransfer) ────────────────────────
//     Pre-launch rules (bridgeConverterActive=false):
//       • feecurrencyid  must be VRSC
//       • fees           must be verusTransactionFee (2000000)
//       • destcurrencyid must be VRSC
//
//     Launched rules (bridgeConverterActive=true):
//       • feecurrencyid  must be VETH
//       • fees           must be verusvETHTransactionFee (300000)
//       • destcurrencyid must be BRIDGE
//       • destinationtype must be DEST_PKH (2) or DEST_ID (4)
//       • destinationaddress must be exactly 20 bytes
function buildTransferStruct(tokenIaddressHex, tokenAmountSats, bridgeConverterActive) {
    return {
        version      : 1,
        currencyvalue: {
            currency: tokenIaddressHex,
            amount  : tokenAmountSats,
        },
        flags         : VALID,
        feecurrencyid : bridgeConverterActive ? TESTNET.VETH : TESTNET.VRSC,
        fees          : bridgeConverterActive ? VETH_TX_FEE_SATS : VERUS_TX_FEE_SATS,
        destination   : {
            destinationtype   : DEST_PKH,
            
            destinationaddress: '0x' + DEST_ADDR_HEX,
        },
        destcurrencyid : bridgeConverterActive ? TESTNET.BRIDGE : TESTNET.VRSC,
        destsystemid   : '0x0000000000000000000000000000000000000000',
        secondreserveid: '0x0000000000000000000000000000000000000000',
    };
}

// ─── Mirror of VerusConstants.convertFromVerusNumber ─────────────────────────
//     Converts a Verus 8-decimal satoshi amount to the token's native wei amount.
function convertFromVerusNumber(amountSats, decimals) {
    const a = BigInt(amountSats);
    if (decimals > 8) return a * (10n ** BigInt(decimals - 8));
    if (decimals < 8) return a / (10n ** BigInt(8 - decimals));
    return a;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
function separator(title) {
    console.log(`\n${'─'.repeat(60)}`);
    console.log(`  ${title}`);
    console.log('─'.repeat(60));
}

async function approveAndTransfer(web3, tokenAbi, tokenAddr, delegatorAddr, amountWei, transferStruct, from) {
    const token = new web3.eth.Contract(tokenAbi, tokenAddr);

    const name = await token.methods.name().call();
    console.log(`  Token:    ${name} @ ${tokenAddr}`);
    console.log(`  Approve:  ${amountWei.toString()} wei`);

    await token.methods.approve(delegatorAddr, amountWei.toString()).send({
        from,
        gas: 100000,
    });
    console.log('  ✓ Approval confirmed');

    const delegatorArtifact = require('../build/contracts/Delegator.json');
    const delegator = new web3.eth.Contract(delegatorArtifact.abi, delegatorAddr);

    const receipt = await delegator.methods.sendTransfer(transferStruct).send({
        from,
        gas  : 6000000,
        value: TX_FEE_WEI,
    });
    console.log(`  ✓ sendTransfer TX: ${receipt.transactionHash}`);
    console.log(`     Block: ${receipt.blockNumber}`);
}

async function sendTransferStruct(delegator, transferStruct, from, msgValue, label) {
    const receipt = await delegator.methods.sendTransfer(transferStruct).send({
        from,
        gas  : 6000000,
        value: msgValue,
    });
    console.log(`  ✓ ${label} TX: ${receipt.transactionHash}`);
    console.log(`     Block: ${receipt.blockNumber}`);
    return receipt;
}

// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
    // ── Connect ───────────────────────────────────────────────────────────────
    let rpcUrl = DEFAULT_RPC;
    let delegatorAddress;

    if (fs.existsSync(STATE_FILE)) {
        const state  = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
        rpcUrl           = state.rpcUrl;
        delegatorAddress = state.delegatorAddress;
    }

    const web3 = new Web3(rpcUrl);

    try {
        const block = await web3.eth.getBlockNumber();
        console.log(`Connected to Ganache at ${rpcUrl}  (latest block: ${block})`);
    } catch {
        console.error(`Cannot connect to Ganache at ${rpcUrl}`);
        console.error('Run `node testnet/start-ganache.js` first.');
        process.exit(1);
    }

    const accounts = await web3.eth.getAccounts();
    const from     = accounts[0];
    console.log(`Sender account: ${from}`);

    // ── Load Delegator ────────────────────────────────────────────────────────
    if (!delegatorAddress) {
        const DelegatorArtifact = require('../build/contracts/Delegator.json');
        const networkIds  = Object.keys(DelegatorArtifact.networks);
        if (!networkIds.length) {
            console.error('No deployed Delegator found. Run migrations first.');
            process.exit(1);
        }
        delegatorAddress = DelegatorArtifact.networks[networkIds[networkIds.length - 1]].address;
    }
    console.log(`Delegator:      ${delegatorAddress}`);

    const DelegatorArtifact = require('../build/contracts/Delegator.json');
    const delegator = new web3.eth.Contract(DelegatorArtifact.abi, delegatorAddress);

    const TokenArtifact = require('../build/contracts/Token.json');
    const bridgeConverterActive = await delegator.methods.bridgeConverterActive().call();
    console.log(`Bridge active:   ${bridgeConverterActive}`);
    console.log(`Fee mode:        ${bridgeConverterActive ? 'launched (vETH fees, Bridge destination)' : 'prelaunch (VRSC fees, VRSC destination)'}`);

    // ──────────────────────────────────────────────────────────────────────────
    // Transfer 1: 1 vETH
    // ──────────────────────────────────────────────────────────────────────────
    separator(`Transfer 1 – Send 1 vETH via ${bridgeConverterActive ? 'sendTransfer' : 'sendTransferDirect'}`);
    try {
        console.log(`  msg.value:  ${Web3.utils.fromWei(VETH_MSG_VALUE, 'ether')} ETH`);

        let receipt;
        if (bridgeConverterActive) {
            const transferStruct = buildTransferStruct(TESTNET.VETH, VETH_AMOUNT_SATS, true);
            receipt = await sendTransferStruct(delegator, transferStruct, from, VETH_MSG_VALUE, 'sendTransfer');
        } else {
            const vethTransfer  = buildPrelaunchVethTransfer();
            const serializedHex = `0x${vethTransfer.toBuffer().toString('hex')}`;

            console.log(`  Serialized: ${serializedHex.slice(0, 40)}…`);

            receipt = await delegator.methods.sendTransferDirect(serializedHex).send({
                from,
                gas  : 6000000,
                value: VETH_MSG_VALUE,
            });
            console.log(`  ✓ TX: ${receipt.transactionHash}`);
            console.log(`     Block: ${receipt.blockNumber}`);
        }

        // Verify the export was recorded
        if (receipt) {
            const exports = await delegator.methods.getReadyExportsByRange(0, receipt.blockNumber + 10).call();
            if (exports.length > 0) {
                console.log(`  ✓ Export recorded – endHeight: ${exports[exports.length - 1].endHeight}`);
            }
        }
    } catch (err) {
        console.error('  ✗ Failed:', err.message);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Transfer 2: 10 DAI via sendTransfer
    // ──────────────────────────────────────────────────────────────────────────
    separator('Transfer 2 – Send 10 DAI via sendTransfer');
    try {
        // Resolve the deployed DAI ERC20 contract address from the bridge mapping
        const daiMapping    = await delegator.methods.verusToERC20mapping(TESTNET.DAI).call();
        const daiERC20Addr  = daiMapping.erc20ContractAddress;

        if (daiERC20Addr === '0x0000000000000000000000000000000000000000') {
            console.error('  ✗ DAI not registered in the bridge – check deployment.');
        } else {
            const daiToken    = new web3.eth.Contract(TokenArtifact.abi, daiERC20Addr);
            const decimals    = parseInt(await daiToken.methods.decimals().call());
            const amountWei   = convertFromVerusNumber(DAI_AMOUNT_SATS, decimals);

            const transferStruct = buildTransferStruct(TESTNET.DAI, DAI_AMOUNT_SATS, bridgeConverterActive);
            await approveAndTransfer(web3, TokenArtifact.abi, daiERC20Addr, delegatorAddress, amountWei, transferStruct, from);
        }
    } catch (err) {
        console.error('  ✗ Failed:', err.message);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Transfer 3: 1 MKR via sendTransfer
    // ──────────────────────────────────────────────────────────────────────────
    separator('Transfer 3 – Send 1 MKR via sendTransfer');
    try {
        const mkrMapping    = await delegator.methods.verusToERC20mapping(TESTNET.MKR).call();
        const mkrERC20Addr  = mkrMapping.erc20ContractAddress;

        if (mkrERC20Addr === '0x0000000000000000000000000000000000000000') {
            console.error('  ✗ MKR not registered in the bridge – check deployment.');
        } else {
            const mkrToken    = new web3.eth.Contract(TokenArtifact.abi, mkrERC20Addr);
            const decimals    = parseInt(await mkrToken.methods.decimals().call());
            const amountWei   = convertFromVerusNumber(MKR_AMOUNT_SATS, decimals);

            const transferStruct = buildTransferStruct(TESTNET.MKR, MKR_AMOUNT_SATS, bridgeConverterActive);
            await approveAndTransfer(web3, TokenArtifact.abi, mkrERC20Addr, delegatorAddress, amountWei, transferStruct, from);
        }
    } catch (err) {
        console.error('  ✗ Failed:', err.message);
    }

    console.log('\nAll transfers complete.\n');
}

// ─── advanceChain ─────────────────────────────────────────────────────────────
// Mines `count` blocks by sending tiny random ETH transfers between ganache
// accounts.  Call directly:
//   node testnet/send-transfers.js advance [count]
//
// Or require and call from other scripts:
//   const { advanceChain } = require('./send-transfers');
//   await advanceChain(web3, 10);
// ─────────────────────────────────────────────────────────────────────────────
async function advanceChain(web3, count = 10) {
    const accounts = await web3.eth.getAccounts();
    const n        = accounts.length;
    const before   = await web3.eth.getBlockNumber();

    console.log(`\nAdvancing chain by ${count} block(s) (currently at block ${before})…`);

    for (let i = 0; i < count; i++) {
        const from = accounts[i % n];
        // pick a different account as recipient
        const to   = accounts[(i + 1) % n];
        // random amount between 0.0001 and 0.001 ETH
        const wei  = BigInt(Math.floor(1e14 + Math.random() * 9e14)).toString();

        await web3.eth.sendTransaction({ from, to, value: wei, gas: 21000 });
    }

    const after = await web3.eth.getBlockNumber();
    console.log(`Chain advanced: block ${before} → ${after}\n`);
    return after;
}

// ─── CLI entry-point ──────────────────────────────────────────────────────────
async function runCLI() {
    const STATE_FILE_CLI = path.join(__dirname, '.testnet-state.json');
    let rpcUrl = DEFAULT_RPC;
    if (fs.existsSync(STATE_FILE_CLI)) {
        rpcUrl = JSON.parse(fs.readFileSync(STATE_FILE_CLI, 'utf8')).rpcUrl;
    }
    const web3 = new Web3(rpcUrl);

    const args  = process.argv.slice(2);
    const cmd   = args[0];

    if (cmd === 'advance') {
        const count = parseInt(args[1]) || 10;
        await advanceChain(web3, count);
    } else {
        await main();
    }
}

if (require.main === module) {
    runCLI().catch(err => { console.error(err); process.exit(1); });
}

module.exports = { advanceChain };
