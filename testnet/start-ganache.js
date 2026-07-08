'use strict';
/**
 * start-ganache.js
 *
 * Starts a persistent Ganache v7 local testnet (London hardfork).
 *
 * • Chain state is saved to  testnet/.ganache-db  – survives restarts.
 * • Accounts are deterministic (same keys every time).
 * • If the server crashes it automatically restarts and reattaches to the
 *   same on-disk chain – no re-deployment needed.
 * • Truffle migrations only run on the very first start (or after --reset).
 *
 * Usage:
 *   node testnet/start-ganache.js           # normal start / resume
 *   node testnet/start-ganache.js --reset   # wipe db and redeploy fresh
 *
 * After startup, run transfers in a second terminal:
 *   node testnet/send-transfers.js
 */

// Raise the global EventEmitter limit before loading anything so that
// Ganache's internal listeners (and Truffle's migration connections) don't
// trigger the MaxListenersExceededWarning.
require('events').EventEmitter.defaultMaxListeners = 50;

const ganache    = require('ganache');
const { spawn }  = require('child_process');
const path       = require('path');
const fs         = require('fs');

const PORT       = 8545;
const CHAIN_ID   = 1337;
const ROOT       = path.resolve(__dirname, '..');
const DB_PATH    = path.join(__dirname, '.ganache-db');
const STATE_FILE = path.join(__dirname, '.testnet-state.json');

// ─── CLI flags ────────────────────────────────────────────────────────────────
const FORCE_RESET = process.argv.includes('--reset');

// ─── Ganache v7 server options ────────────────────────────────────────────────
function buildServerOptions() {
    return {
        chain: {
            hardfork               : 'london',
            chainId                : CHAIN_ID,
            allowUnlimitedContractSize: true,   // SubmitImports > EIP-170 24 KB
        },
        wallet: {
            deterministic : true,   // fixed accounts / private keys across restarts
            totalAccounts : 10,
            defaultBalance: 10000,  // 10,000 ETH per account
        },
        database: {
            dbPath: DB_PATH,        // persist chain state to disk
        },
        miner: {
            blockGasLimit: 150000000,
        },
        logging: {
            quiet: true,
        },
    };
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
function banner(msg) {
    const line = '─'.repeat(60);
    console.log(`\n${line}\n  ${msg}\n${line}`);
}

function runAsync(cmd, args, cwd) {
    return new Promise((resolve, reject) => {
        const child = spawn(cmd, args, { cwd, stdio: 'inherit', shell: false });
        child.on('exit', code => {
            if (code === 0) resolve();
            else reject(new Error(`"${cmd} ${args.join(' ')}" exited with code ${code}`));
        });
        child.on('error', reject);
    });
}

function wipeDb() {
    if (fs.existsSync(DB_PATH)) {
        fs.rmSync(DB_PATH, { recursive: true, force: true });
        console.log('  Wiped existing chain database.');
    }
    if (fs.existsSync(STATE_FILE)) fs.unlinkSync(STATE_FILE);
}

// Is this the very first start (no db on disk yet, or db is empty)?
function isFirstStart() {
    if (!fs.existsSync(STATE_FILE)) return true;
    if (!fs.existsSync(DB_PATH))    return true;
    // An existing but empty directory is the same as no db
    try { if (fs.readdirSync(DB_PATH).length === 0) return true; } catch {}
    return false;
}

// ─── Single server lifecycle ──────────────────────────────────────────────────
async function startOnce(getServer) {
    const server = ganache.server(buildServerOptions());
    getServer(server);   // expose the server reference to the shutdown handler

    await server.listen(PORT);

    const provider        = server.provider;
    const initialAccounts = provider.getInitialAccounts();
    const addresses       = Object.keys(initialAccounts);

    // Print account / connection info every start so the user can reconnect
    console.log(`\nRPC URL  : http://127.0.0.1:${PORT}`);
    console.log(`Chain ID : ${CHAIN_ID}   Hardfork : London`);
    console.log('\nAccounts (deterministic – same every restart):');
    addresses.forEach((addr, i) => {
        const info = initialAccounts[addr];
        console.log(`  [${i}] ${addr}`);
        console.log(`      Private key: ${info.secretKey}`);
    });

    // ── Deploy contracts (first start only) ───────────────────────────────────
    if (isFirstStart()) {
        banner('First start – deploying contracts via Truffle');
        try {
            await runAsync(
                'npx',
                ['truffle', 'migrate', '--network', 'development', '--reset'],
                ROOT,
            );
        } catch (err) {
            console.error('\n✗ Migration failed.');
            throw err;
        }

        // Read delegator address from freshly-updated build artifact
        const delegatorPath = path.join(ROOT, 'build', 'contracts', 'Delegator.json');
        delete require.cache[delegatorPath];
        const artifact      = require(delegatorPath);
        const networkIds    = Object.keys(artifact.networks);
        const networkId     = networkIds[networkIds.length - 1];
        const delegatorAddr = artifact.networks[networkId].address;

        const state = {
            rpcUrl          : `http://127.0.0.1:${PORT}`,
            chainId         : CHAIN_ID,
            networkId       : parseInt(networkId, 10),
            delegatorAddress: delegatorAddr,
            accounts        : addresses.map((addr, i) => ({
                address   : addr,
                privateKey: initialAccounts[addr].secretKey,
                index     : i,
            })),
        };
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));

        banner('Testnet ready (first deployment)');
        console.log(`Delegator : ${delegatorAddr}`);
    } else {
        const state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
        banner('Testnet resumed (chain loaded from disk)');
        console.log(`Delegator : ${state.delegatorAddress}`);
    }

    const state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    console.log(`\nRPC URL   : http://127.0.0.1:${PORT}`);
    console.log(`Delegator : ${state.delegatorAddress}`);
    console.log(`\nTo connect with Web3:`);
    console.log(`  const web3 = new Web3('http://127.0.0.1:${PORT}');`);
    console.log(`\nTo send test transfers:`);
    console.log(`  node testnet/send-transfers.js`);
    console.log(`\nTo wipe and redeploy from scratch:`);
    console.log(`  node testnet/start-ganache.js --reset`);
    console.log(`\nPress Ctrl+C to stop.\n`);

    // Wait until the server closes on its own (unexpected crash → triggers restart)
    await new Promise(resolve => server.on('close', resolve));
}

// ─── Main (auto-restart loop) ─────────────────────────────────────────────────
async function main() {
    banner('Verus Bridge Local Testnet');

    if (FORCE_RESET) {
        console.log('  --reset flag detected: wiping existing chain database…');
        wipeDb();
    }

    // Keep a reference to the current server so the SIGINT handler can reach it
    let currentServer  = null;
    let shuttingDown   = false;

    // ── SIGINT handler ─────────────────────────────────────────────────────────
    // Must be synchronous-enough to actually exit: kick off the close, then
    // force-exit after 3 s regardless so a hung server never blocks Ctrl+C.
    process.on('SIGINT', () => {
        if (shuttingDown) return;
        shuttingDown = true;
        console.log('\nStopping Ganache…');

        const forceExit = setTimeout(() => {
            console.log('Force-exiting (server close timed out).');
            process.exit(0);
        }, 3000);
        forceExit.unref(); // don't prevent exit if close finishes first

        const doClose = async () => {
            if (currentServer) {
                try { await currentServer.close(); } catch {}
            }
            clearTimeout(forceExit);
            console.log('Goodbye.');
            process.exit(0);
        };
        doClose();
    });

    // ── Restart loop ──────────────────────────────────────────────────────────
    let attempt = 0;
    while (!shuttingDown) {
        attempt++;
        if (attempt > 1) {
            console.log(`\nRestarting Ganache (attempt ${attempt})… chain state preserved on disk.\n`);
            await new Promise(r => setTimeout(r, 3000));
            if (shuttingDown) break;
        }

        try {
            await startOnce(s => { currentServer = s; });
            currentServer = null;
        } catch (err) {
            currentServer = null;
            if (shuttingDown) break;
            console.error(`\nGanache error: ${err.message}`);
            console.log('Will restart automatically in 3 s…');
        }
    }
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});

