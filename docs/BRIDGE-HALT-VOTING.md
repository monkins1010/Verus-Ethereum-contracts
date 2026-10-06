# Bridge Halt Voting

Authoritative description of the bridge halt states, what triggers and clears them, and which endpoints notaries call.
Source of truth in code: [`BridgeHalt.sol`](../Verus-Ethereum-contracts/contracts/Libraries/BridgeHalt.sol) (states and keys),
[`NotaryTools.sol`](../Verus-Ethereum-contracts/contracts/VerusNotarizer/NotaryTools.sol) (revocation trigger) and
[`PendingImports.sol`](../Verus-Ethereum-contracts/contracts/VerusBridge/PendingImports.sol) (voting).
Tests: [`test/bridgeHalt.js`](../Verus-Ethereum-contracts/test/bridgeHalt.js).

`Delegator.sol` is fixed and unchanged. Votes are calls to `Delegator.setVerusData(bytes data, string route)`, which
resolves `route` through `VerusCrossChainExport.checkVDFXId` and `delegatecall`s `<route>(bytes)` on the registered contract.

## 1. The states

| State | Name in code | Entered by | Left by |
|---|---|---|---|
| Normal | `CONTRACTS_NORMAL` (0) | - | - |
| **Bridge Temporary Halted** | `CONTRACTS_TEMPORARY_HALTED` (1) | **4 or more notaries revoked** (notaries revoking themselves, or by multisig) | `submitUnhaltVote(true)` from a **quorum** of *valid* notaries |
| **Bridge Permanently Halted** | `CONTRACTS_PERMANENTLY_HALTED` (2) | `approveOrRejectAcceptedImport(txid, false)` from a **quorum** of notaries on the same bad import txid (automatic, already exists) | **Contract upgrade only**: `PendingImports.initialize()` clears the blocked txid |

* Quorum = `(notaries.length >> 1) + 1`.
* There is **no halt vote**. A temporary halt happens when the number of revoked notaries reaches the threshold, checked on every revoke
  (`revokeWithMainAddress`, `revokeWithMultiSig`). Threshold is `min(4, notaries.length)`, i.e. "more than 3" on any real notary set;
  the cap only lets the 3-notary dev/Sepolia sets halt too.
* Recovering notaries (`recoverWithRecoveryAddress` / `recoverWithMultiSig`) does **not** lift a temporary halt. Revoked notaries recover themselves in their own time,
  and a quorum of valid notaries then votes to unhalt.
* The two states are mutually exclusive. Entering the permanent halt **clears the temporary halt and its unhalt votes**, and closes `submitUnhaltVote` until an upgrade
  lifts the permanent halt. While permanently halted, revoking notaries does not start a temporary halt (it would stop the notarizations an upgrade needs).
* **Revoked notaries cannot vote at all** (unhalt votes, import approve/reject votes, rescinds), and votes they cast before being revoked are not counted
  while they are revoked. They count again if the notary recovers.

## 2. What each state blocks

| Function | Normal | Temporary Halted | Permanently Halted |
|---|---|---|---|
| `submitImports` | ok | **blocked** | **blocked** |
| `sendTransfer` / `sendTransferDirect` | ok | **blocked** | **blocked** |
| `setLatestData` (notarizations, incl. upgrade votes carried in them) | ok | **blocked** | **ok** (needed to vote in the upgrade) |
| Pending import approve vote / `executeTimedOutImport` | ok | **blocked** | **blocked** |
| Pending import **reject** vote | ok | ok (raises the halt to permanent) | blocked (already permanent) |
| `submitUnhaltVote` (true or false) | reverts | ok | **reverts** (endpoint closed) |
| `claimfees`, `sendfees`, `burnFees` (DAI), `claimRefund`, `getProof`, `upgradeContracts`, revoke/recover | ok | ok | ok |

Utility functions are deliberately not gated. Note `claimfees` / `sendfees` / `claimRefund` can still pay out accrued fees and refunds while halted.

Gates are bit flags in `claimableFees[VDXF_DISABLE_CONTRACT_KEY]` (`1` notarizations, `2` submitImports, `4` sendTransfer). They are **derived** by
`BridgeHalt.refreshFlags` from the state keys and never written directly:

| State | Flags |
|---|---|
| Normal | `0` |
| Temporary Halted | `7` |
| Permanently Halted | `6` |

## 3. Temporary halt

```
notaries revoke (self or multisig): the revocation that brings revoked >= 4  -> CONTRACTS_TEMPORARY_HALTED   (BridgeTemporarilyHalted event)
valid notaries xQ: setVerusData(abi.encode(true), "submitUnhaltVote")       -> Q-th valid vote clears it     (BridgeTemporarilyUnhalted event)
```

* A notary revokes itself with `Delegator.revokeWithMainAddress(bytes)` (any bytes, e.g. `0x`), sent from its **main** ETH address. It is then revoked until it
  recovers with its recovery key. A manual halt is therefore 4 notaries revoking themselves.
* The unhalt counter is a `uint32` bitmap, one bit per notary index, so a notary is never counted twice. Only valid (not revoked) notaries' bits are counted.
* `submitUnhaltVote(false)` rescinds your own unhalt vote while still halted.
* The halt clears when `valid unhalt votes >= quorum` **and** fewer notaries are revoked than the halt threshold. With 8 notaries the first condition already
  implies the second; with larger sets, revoked notaries must recover first. The check runs on each unhalt vote, so re-send a vote after a recovery if needed.
* On unhalt, the temporary halt and the unhalt votes are cleared. The bridge is **not** re-halted until the next revoke is processed, so recover revoked notaries before
  relying on the full notary set.
* Unhalt votes are not tied to a time window; they stay until rescinded or the halt is cleared.

## 4. Permanent halt (automatic, already exists)

A notary that sees a transfer discrepancy rejects the pending import for the bad transaction:

```
notary xQ:  setVerusData(abi.encode(bytes32 badImportTxid, false), "approveOrRejectAcceptedImport")
```

* When valid reject votes on that txid reach quorum: the import is marked `REJECTED` (stays in the queue, can never execute or be re-queued),
  `storageGlobal[bridge.permanently.halted] = abi.encode(badImportTxid)` is set, any temporary halt and its unhalt votes are cleared,
  flags become `6`, and `BridgePermanentlyHalted(txid)` + `PendingImportRejected(txid)` are emitted.
* `submitImports` and `sendTransfer*` stop, so no value moves in or out. `setLatestData` keeps working so notarizations (and the upgrade vote) can go in.
* The only exit is an upgrade that replaces the `PendingImports` contract: the upgrade calls its `initialize()`, which deletes the blocked txid
  and recomputes the flags. **Any** upgrade of `PendingImports` lifts the permanent halt; this is by design, so only upgrade it once the cause is fixed.
* After the upgrade the bridge is normal. If 4 or more notaries are still revoked at that point, the temporary halt is only re-applied on the next revoke.

## 5. Endpoints for the notary API

Votes are `Delegator.setVerusData(bytes data, string route)`; sender must be a valid notary main address.

| Route / function | `data` encoding | Effect |
|---|---|---|
| `Delegator.revokeWithMainAddress(bytes)` | any bytes (`0x`) | revoke yourself; the 4th revoked notary halts the bridge |
| `setVerusData(.., "submitUnhaltVote")` | `abi.encode(bool voteToUnhalt)` | only while temporarily halted; quorum of valid notaries clears the halt |
| `setVerusData(.., "approveOrRejectAcceptedImport")` | `abi.encode(bytes32 importTxid, bool approve)` | `false` = reject vote (permanent halt at quorum). `true` = approve, blocked while halted |

Txid byte order: the bridgekeeper passes the Verus txid byte-reversed (`ethInteractor.approveOrRejectAcceptedImport`).

### Reading the state (no transaction)

`setVerusData` returns nothing, so read state through the public getters on the Delegator:

| What | Call | Value |
|---|---|---|
| Gate flags | `claimableFees(0x000000000000000000000000b024b1e290c833d9c5703ef6184a7c84e7ddd335)` | `0`, `6` or `7` |
| Temporarily halted | `storageGlobal(0xe1062f0ad08aee861a65b0586bf7df4b1be6575fb927fb5da459a3383d597c27)` | non-empty = halted |
| Permanently halted + blocked txid | `storageGlobal(0x087558cbb31fc6b87e2c3ecf8141e6fd7d66c9d747e7ac3f093e17a5ed2c397d)` | `abi.encode(bytes32 txid)`, empty = not halted |
| Unhalt votes bitmap | `storageGlobal(0xe2835974332c677006ec892a78804605ad49a7f03463b0ca5a5124d48b8d1b5e)` | `abi.encode(uint32)` (includes bits of notaries revoked since voting) |
| Notary state | `notaryAddressMapping(iaddress)` | `.state`: 1 valid, 2 revoked |

An unset `storageGlobal` slot is returned as `null` by truffle-contract and `'0x'` by web3. Keys are `keccak256` of the names `bridge.temporary.halted`,
`bridge.permanently.halted`, `bridge.unhalt.vote.bitmap`.

### Events (emitted by the Delegator, ABI = `PendingImports.json`)

`BridgeTemporarilyHalted()`, `UnhaltVoteSubmitted(notarizerID, voteToUnhalt, voteCount, temporarilyHalted)`, `BridgeTemporarilyUnhalted()`,
`BridgePermanentlyHalted(bytes32 blockedTxid)`, `PendingImportRejectVote`, `PendingImportRejected`.
These are **not** in the Delegator ABI, so decode `receipt.logs` with the `PendingImports` ABI.

### Failure behaviour

`Delegator` does `require(success)` on every delegatecall, so **revert reasons are lost**; all failures are a bare revert. Run the call with `.call()` /
`estimateGas()` first (as the bridgekeeper does) and read the state above to explain a failure. Typical causes:
sender is a revoked notary or not a notary; unhalt vote while not temporarily halted; unhalt vote while permanently halted.

## 6. `haltbridge.js` example

`node haltbridge.js status`, `node haltbridge.js revoke` (self-revoke: your contribution to a temporary halt; irreversible without your recovery key),
`node haltbridge.js unhalt`, `node haltbridge.js unhalt-rescind`.

```js
// haltbridge.js
const Web3 = require('web3');
const delegatorAbi = require('./abi/Delegator.json'); // Delegator ABI (array or {abi})

const web3 = new Web3(process.env.ETH_RPC);                       // e.g. https://sepolia.infura.io/v3/<key>
const account = web3.eth.accounts.privateKeyToAccount(process.env.NOTARY_PRIVKEY); // notary MAIN address key
web3.eth.accounts.wallet.add(account);
const delegator = new web3.eth.Contract(delegatorAbi.abi || delegatorAbi, process.env.DELEGATOR);

const K = {
  flags: '0x000000000000000000000000b024b1e290c833d9c5703ef6184a7c84e7ddd335',
  temporary: web3.utils.keccak256('bridge.temporary.halted'),
  permanent: web3.utils.keccak256('bridge.permanently.halted'),
  unhaltVotes: web3.utils.keccak256('bridge.unhalt.vote.bitmap'),
};
const isSet = (v) => v !== null && v !== '0x' && v !== '';
const bits = (v) => (isSet(v) ? BigInt(web3.eth.abi.decodeParameter('uint32', v)).toString(2).replace(/0/g, '').length : 0);

async function status() {
  const [flags, temp, perm, uv] = await Promise.all([
    delegator.methods.claimableFees(K.flags).call(),
    delegator.methods.storageGlobal(K.temporary).call(),
    delegator.methods.storageGlobal(K.permanent).call(),
    delegator.methods.storageGlobal(K.unhaltVotes).call(),
  ]);
  const state = isSet(perm) ? 'CONTRACTS_PERMANENTLY_HALTED' : isSet(temp) ? 'CONTRACTS_TEMPORARY_HALTED' : 'NORMAL';
  console.log({ state, flags, unhaltVotes: bits(uv),
    blockedTxid: isSet(perm) ? web3.eth.abi.decodeParameter('bytes32', perm) : null });
}

async function submit(tx) {
  await tx.call({ from: account.address });                       // reverts (bare) if the call would fail
  const gas = Math.ceil(Number(await tx.estimateGas({ from: account.address })) * 1.3);
  const receipt = await tx.send({ from: account.address, gas });
  console.log('tx', receipt.transactionHash);
}

(async () => {
  const cmd = process.argv[2] || 'status';
  const unhalt = (v) => delegator.methods.setVerusData(web3.eth.abi.encodeParameter('bool', v), 'submitUnhaltVote');
  if (cmd === 'revoke') await submit(delegator.methods.revokeWithMainAddress('0x'));
  else if (cmd === 'unhalt') await submit(unhalt(true));
  else if (cmd === 'unhalt-rescind') await submit(unhalt(false));
  else if (cmd !== 'status') throw new Error('usage: node haltbridge.js [status|revoke|unhalt|unhalt-rescind]');
  await status();
})().catch((e) => { console.error(e.message); process.exit(1); });
```

The bridgekeeper already has the automatic permanent-halt path (`approveOrRejectAcceptedImport` in `ethInteractor.js`); nothing else is needed for it.

## 7. Deploying / upgrading

* Replace **`PendingImports`** (slot 11) and **`NotaryTools`** (slot 6). Replacing `PendingImports` runs its `initialize()`, which registers
  `submitUnhaltVote` and rebuilds the flags (**this also lifts a permanent halt**, see section 4).
  It does not clean up older routes or keys: an existing deployment keeps stale `haltBridge` / `resumeBridge` / `submitHaltVote` route entries
  (they now revert, as those functions no longer exist) and the unused `bridge.import.paused` key (nothing reads it).
* `UpgradeManager` and `VerusCrossChainExport` were edited so that *fresh* deployments register the new routes and stop registering the removed ones;
  an existing deployment does not need them replaced.
* Removed: `NotaryTools.haltBridge` / `resumeBridge` (signature based halt/resume) and the `submitHaltVote` vote, so a temporary halt has a single trigger.
* `PendingImports` deployed size is about 22.6 KB (limit 24.576 KB, unoptimized build).
