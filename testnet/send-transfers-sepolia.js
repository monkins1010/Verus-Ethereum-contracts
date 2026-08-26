'use strict';
/**
 * send-transfers-sepolia.js
 *
 * Connects to Sepolia testnet and sends three example reserve transfers
 * to the deployed Verus Bridge Delegator contract:
 *
 *   1. 1 vETH  – via sendTransferDirect or sendTransfer (depending on bridge state)
 *   2. 10 DAI  – via sendTransfer (ABI-encoded CReserveTransfer struct)
 *   3. 1  MKR  – via sendTransfer (ABI-encoded CReserveTransfer struct)
 *
 * Usage:
 *   node testnet/send-transfers-sepolia.js
 *
 * Environment variables (optional):
 *   BRIDGE_CONTRACT  - Delegator contract address (default: 0x22f91dC774aF63C0ad92ad397aCaadEFD0221674)
 *   PRIVATE_KEY      - Private key to use for sending (default: from truffle-config.js)
 *   SEPOLIA_RPC      - Sepolia RPC URL (default: from truffle-config.js)
 */

const Web3 = require('web3');
const { CurrencyValueMap, ReserveTransfer, TransferDestination } = require('verus-typescript-primitives');
const BN   = require('bn.js');

// ─── Config ───────────────────────────────────────────────────────────────────
const BRIDGE_CONTRACT = process.env.BRIDGE_CONTRACT || '0x22f91dC774aF63C0ad92ad397aCaadEFD0221674';
const PRIVATE_KEY     = process.env.PRIVATE_KEY;
const SEPOLIA_RPC     = process.env.SEPOLIA_RPC || 'https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY';

// ─── Verus testnet currency iaddresses (hex / uint160) ────────────────────────
const TESTNET = {
    VETH  : '0x67460C2f56774eD27EeB8685f29f6CEC0B090B00',
    VRSC  : '0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d',
    BRIDGE: '0xffEce948b8A38bBcC813411D2597f7f8485a0689',
    DAI   : '0xcce5d18f305474f1e0e0ec1c507d8c85e7315fdf',
    MKR   : '0x005005b2b10a897fed36fbd71c878213a7a169bf',
};

// ─── Verus base58 i-addresses ─────────────────────────────────────────────────
const IADDR_VETH = 'iCtawpxUiCc2sEupt7Z4u8SDAncGZpgSKm';
const IADDR_VRSC = 'iJhCezBExJHvtyH3fGhNnt2NhU4Ztkf2yq';

// ─── Transfer constants ───────────────────────────────────────────────────────
const VALID             = 1;
const DEST_PKH          = 2;
const TX_FEE_WEI        = '3000000000000000';   // 0.003 ETH
const VERUS_TX_FEE_SATS = 2000000;              // 0.02 VRSC
const VETH_TX_FEE_SATS  = 300000;               // 0.003 vETH

// Destination address (20 bytes, no 0x)
const DEST_ADDR_HEX = '55f51a22c79018a00ced41e758560f5df7d4d35d';

// vETH amount: 1 ETH in Verus 8-decimal satoshis
const VETH_AMOUNT_SATS  = 1000000000;
const VETH_MSG_VALUE    = Web3.utils.toWei('1.003', 'ether');

// DAI amount: 10 DAI in Verus 8-decimal satoshis
const DAI_AMOUNT_SATS   = 1000000000000;
// MKR amount: 1 MKR in Verus 8-decimal satoshis
const MKR_AMOUNT_SATS   =  10000000000;

// ─── ReserveTransfer builder (prelaunch only) ─────────────────────────────────
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

// ─── CReserveTransfer struct builder ──────────────────────────────────────────
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

// ─── Helpers ──────────────────────────────────────────────────────────────────
function convertFromVerusNumber(amountSats, decimals) {
    const a = BigInt(amountSats);
    if (decimals > 8) return a * (10n ** BigInt(decimals - 8));
    if (decimals < 8) return a / (10n ** BigInt(8 - decimals));
    return a;
}

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

    const approveTx = await token.methods.approve(delegatorAddr, amountWei.toString()).send({
        from,
        gas: 100000,
    });
    console.log(`  ✓ Approval TX: ${approveTx.transactionHash}`);

    const DelegatorArtifact = require('../build/contracts/Delegator.json');
    const delegator = new web3.eth.Contract(DelegatorArtifact.abi, delegatorAddr);

    const receipt = await delegator.methods.sendTransfer(transferStruct).send({
        from,
        gas  : 6000000,
        value: TX_FEE_WEI,
    });
    console.log(`  ✓ sendTransfer TX: ${receipt.transactionHash}`);
    console.log(`     Block: ${receipt.blockNumber}`);
    return receipt;
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
    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Verus Bridge - Sepolia Reserve Transfer Script');
    console.log('═══════════════════════════════════════════════════════════\n');

    // ── Connect ───────────────────────────────────────────────────────────────
    const web3 = new Web3(new Web3.providers.HttpProvider(SEPOLIA_RPC));
    
    try {
        const block = await web3.eth.getBlockNumber();
        console.log(`Connected to Sepolia (block: ${block})`);
    } catch (err) {
        console.error(`Cannot connect to Sepolia at ${SEPOLIA_RPC}`);
        console.error(err.message);
        process.exit(1);
    }

    // ── Setup account ─────────────────────────────────────────────────────────
    const account = web3.eth.accounts.privateKeyToAccount(PRIVATE_KEY);
    web3.eth.accounts.wallet.add(account);
    const from = account.address;
    
    const balance = await web3.eth.getBalance(from);
    console.log(`Sender:     ${from}`);
    console.log(`Balance:    ${Web3.utils.fromWei(balance, 'ether')} ETH`);
    console.log(`Delegator:  ${BRIDGE_CONTRACT}\n`);

    // ── Load Delegator ────────────────────────────────────────────────────────
    const DelegatorArtifact = require('../build/contracts/Delegator.json');
    const delegator = new web3.eth.Contract(DelegatorArtifact.abi, BRIDGE_CONTRACT);
    
    const TokenArtifact = require('../build/contracts/Token.json');
    
    let bridgeConverterActive;
    try {
        bridgeConverterActive = await delegator.methods.bridgeConverterActive().call();
        console.log(`Bridge active:   ${bridgeConverterActive}`);
        console.log(`Fee mode:        ${bridgeConverterActive ? 'launched (vETH fees)' : 'prelaunch (VRSC fees)'}`);
    } catch (err) {
        console.error('Error reading bridge state:', err.message);
        process.exit(1);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Transfer 1: 1 vETH
    // ──────────────────────────────────────────────────────────────────────────
    separator(`Transfer 1 – Send 1 vETH via ${bridgeConverterActive ? 'sendTransfer' : 'sendTransferDirect'}`);
    try {
        console.log(`  Amount:     1 vETH (${VETH_AMOUNT_SATS} sats)`);
        console.log(`  msg.value:  ${Web3.utils.fromWei(VETH_MSG_VALUE, 'ether')} ETH`);

        let receipt;
        if (bridgeConverterActive) {
            const transferStruct = buildTransferStruct(TESTNET.VETH, VETH_AMOUNT_SATS, true);
            receipt = await sendTransferStruct(delegator, transferStruct, from, VETH_MSG_VALUE, 'sendTransfer');
        } else {
            const vethTransfer  = buildPrelaunchVethTransfer();
            const serializedHex = `0x${vethTransfer.toBuffer().toString('hex')}`;

            console.log(`  Serialized: ${serializedHex.slice(0, 60)}...`);

            receipt = await delegator.methods.sendTransferDirect(serializedHex).send({
                from,
                gas  : 6000000,
                value: VETH_MSG_VALUE,
            });
            console.log(`  ✓ sendTransferDirect TX: ${receipt.transactionHash}`);
            console.log(`     Block: ${receipt.blockNumber}`);
        }

        // Verify export
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
    // Transfer 2: 10 DAI
    // ──────────────────────────────────────────────────────────────────────────
    separator('Transfer 2 – Send 10 DAI via sendTransfer');
    try {
        const daiMapping    = await delegator.methods.verusToERC20mapping(TESTNET.DAI).call();
        const daiERC20Addr  = daiMapping.erc20ContractAddress;

        if (daiERC20Addr === '0x0000000000000000000000000000000000000000') {
            console.error('  ✗ DAI not registered in the bridge');
        } else {
            console.log(`  DAI ERC20:  ${daiERC20Addr}`);
            const daiToken    = new web3.eth.Contract(TokenArtifact.abi, daiERC20Addr);
            const decimals    = parseInt(await daiToken.methods.decimals().call());
            const amountWei   = convertFromVerusNumber(DAI_AMOUNT_SATS, decimals);
            
            const transferStruct = buildTransferStruct(TESTNET.DAI, DAI_AMOUNT_SATS, bridgeConverterActive);
            await approveAndTransfer(web3, TokenArtifact.abi, daiERC20Addr, BRIDGE_CONTRACT, amountWei, transferStruct, from);
        }
    } catch (err) {
        console.error('  ✗ Failed:', err.message);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Transfer 3: 1 MKR
    // ──────────────────────────────────────────────────────────────────────────
    separator('Transfer 3 – Send 1 MKR via sendTransfer');
    try {
        const mkrMapping    = await delegator.methods.verusToERC20mapping(TESTNET.MKR).call();
        const mkrERC20Addr  = mkrMapping.erc20ContractAddress;

        if (mkrERC20Addr === '0x0000000000000000000000000000000000000000') {
            console.error('  ✗ MKR not registered in the bridge');
        } else {
            console.log(`  MKR ERC20:  ${mkrERC20Addr}`);
            const mkrToken    = new web3.eth.Contract(TokenArtifact.abi, mkrERC20Addr);
            const decimals    = parseInt(await mkrToken.methods.decimals().call());
            const amountWei   = convertFromVerusNumber(MKR_AMOUNT_SATS, decimals);
            
            const transferStruct = buildTransferStruct(TESTNET.MKR, MKR_AMOUNT_SATS, bridgeConverterActive);
            await approveAndTransfer(web3, TokenArtifact.abi, mkrERC20Addr, BRIDGE_CONTRACT, amountWei, transferStruct, from);
        }
    } catch (err) {
        console.error('  ✗ Failed:', err.message);
    }

    separator('Summary');
    console.log('  All transfers complete!');
    console.log('  Check transactions on Sepolia Etherscan:');
    console.log(`  https://sepolia.etherscan.io/address/${BRIDGE_CONTRACT}\n`);
}

// ─── CLI entry-point ──────────────────────────────────────────────────────────
if (require.main === module) {
    main().catch(err => {
        console.error('\n✗ Error:', err.message);
        process.exit(1);
    });
}

module.exports = { main };
