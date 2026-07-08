'use strict';

/**
 * random-eth-loop.js
 *
 * Sends 0.001 ETH every 30 seconds to keep Ganache producing blocks.
 *
 * Defaults:
 *   - RPC: http://127.0.0.1:8545 (or testnet/.testnet-state.json rpcUrl)
 *   - Amount: 0.001 ETH
 *   - Interval: 30000 ms
 *   - From/To: random pair from unlocked Ganache accounts
 *
 * Optional flags:
 *   --rpc=http://127.0.0.1:8545
 *   --from=0x...
 *   --to=0x...
 *   --amount=0.001
 *   --interval=30000
 */

const Web3 = require('web3');
const fs = require('fs');
const path = require('path');

const DEFAULT_RPC = 'http://127.0.0.1:8545';
const DEFAULT_AMOUNT_ETH = '0.001';
const DEFAULT_INTERVAL_MS = 30_000;
const STATE_FILE = path.join(__dirname, '.testnet-state.json');

function parseArgs(argv) {
    const out = {};
    for (const arg of argv) {
        if (!arg.startsWith('--')) continue;
        const eq = arg.indexOf('=');
        if (eq === -1) {
            out[arg.slice(2)] = true;
            continue;
        }
        out[arg.slice(2, eq)] = arg.slice(eq + 1);
    }
    return out;
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function pickRandomPair(accounts) {
    const fromIndex = Math.floor(Math.random() * accounts.length);
    let toIndex = Math.floor(Math.random() * accounts.length);
    while (toIndex === fromIndex) {
        toIndex = Math.floor(Math.random() * accounts.length);
    }
    return {
        from: accounts[fromIndex],
        to: accounts[toIndex],
    };
}

async function main() {
    const args = parseArgs(process.argv.slice(2));

    let rpc = args.rpc || DEFAULT_RPC;
    if (!args.rpc && fs.existsSync(STATE_FILE)) {
        try {
            const state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
            if (state.rpcUrl) rpc = state.rpcUrl;
        } catch {
            // Ignore malformed state file and use default RPC.
        }
    }

    const amountEth = args.amount || DEFAULT_AMOUNT_ETH;
    const intervalMs = Number(args.interval || DEFAULT_INTERVAL_MS);
    if (!Number.isFinite(intervalMs) || intervalMs <= 0) {
        throw new Error('Invalid --interval value. Use a positive number in milliseconds.');
    }

    const web3 = new Web3(rpc);
    const accounts = await web3.eth.getAccounts();
    if (accounts.length < 2) {
        throw new Error('Need at least 2 unlocked accounts to run transfers.');
    }

    const fixedFrom = args.from;
    const fixedTo = args.to;
    if ((fixedFrom && !fixedTo) || (!fixedFrom && fixedTo)) {
        throw new Error('Provide both --from and --to, or neither.');
    }

    if (fixedFrom && !accounts.includes(fixedFrom)) {
        throw new Error('--from address is not one of the unlocked node accounts.');
    }
    if (fixedTo && !accounts.includes(fixedTo)) {
        throw new Error('--to address is not one of the unlocked node accounts.');
    }
    if (fixedFrom && fixedTo && fixedFrom.toLowerCase() === fixedTo.toLowerCase()) {
        throw new Error('--from and --to must be different addresses.');
    }

    const valueWei = web3.utils.toWei(amountEth, 'ether');

    const currentBlock = await web3.eth.getBlockNumber();
    console.log(`Connected: ${rpc}`);
    console.log(`Start block: ${currentBlock}`);
    console.log(`Amount: ${amountEth} ETH`);
    console.log(`Interval: ${intervalMs} ms`);
    if (fixedFrom && fixedTo) {
        console.log(`Mode: fixed pair ${fixedFrom} -> ${fixedTo}`);
    } else {
        console.log('Mode: random unlocked account pair each transfer');
    }
    console.log('Press Ctrl+C to stop.');

    let stopRequested = false;
    process.on('SIGINT', () => {
        if (stopRequested) return;
        stopRequested = true;
        console.log('\nStopping transfer loop...');
    });

    let sent = 0;
    while (!stopRequested) {
        const pair = fixedFrom && fixedTo
            ? { from: fixedFrom, to: fixedTo }
            : pickRandomPair(accounts);

        try {
            const beforeBlock = await web3.eth.getBlockNumber();
            const receipt = await web3.eth.sendTransaction({
                from: pair.from,
                to: pair.to,
                value: valueWei,
                gas: 21000,
            });
            const afterBlock = await web3.eth.getBlockNumber();

            sent += 1;
            console.log(
                `[${sent}] tx=${receipt.transactionHash} block ${beforeBlock} -> ${afterBlock} ${pair.from} -> ${pair.to}`,
            );
        } catch (err) {
            console.error(`[${sent + 1}] transfer failed: ${err.message}`);
        }

        if (!stopRequested) {
            await sleep(intervalMs);
        }
    }

    console.log(`Done. Sent ${sent} transfer(s).`);
}

main().catch(err => {
    console.error(err.message || err);
    process.exit(1);
});
