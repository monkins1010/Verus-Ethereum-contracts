# Contract Build / Initialize() Timeline

> Timeline of all changes made to `initialize()` functions across contracts,
> starting from commit **d633dc403fe44088d83f22628e9d41860c5a668e**.
> Entries are in chronological order (oldest → newest).

---

## 2026-05-22 — `3c88fd6` — "Add fixes for CCE, CompactInt, Proof storage"

No changes to `initialize()` functions in this commit. Baseline state from starting commit:

- **`NotarizationSerializer.sol`** — `rollingVoteIndex = VerusConstants.DEFAULT_INDEX_VALUE;`
- **`NotaryTools.sol`** — wBTC accounting fix: calculated excess wBTC held in contract vs recorded `tokenIndex`, sent 0.05809652 WBTC to owed address `0x16770EafcdBEFf2AE73ccD680694f53a8D40df55`, any remaining excess sent to refund address `0x8727eE29C1C88b5b2a0Fed4721F92Cc9cd44583b`
- **`UpgradeManager.sol`** — `rollingVoteIndex = VerusConstants.DEFAULT_INDEX_VALUE;`
- **`VerusCrossChainExport.sol`** — MakerDAO DAI vault setup: `vat.hope(daiJoin)`, `vat.hope(pot)`, `IERC20(DAIERC20).approve(daiJoin, uint256(int256(-1)))`
- **`VerusSerializer.sol`** — Empty
- **`CreateExports.sol`** — Commented-out DAI DSR correction (already deployed prior to this range): `verusToERC20mapping[DAI].tokenIndex = (claimableFees[...] / SATS_TO_WEI_STD) - verusToERC20mapping[DAI].tokenIndex;`
- **`SubmitImports.sol`** — Empty
- **`TokenManager.sol`** — Empty
- *(VerusProof.sol, ExportManager.sol, VerusNotarizer.sol — no `initialize()` function yet)*

---

## 2026-06-02 — `d12876f` — "Add notarization flags, remove initialized() functions that have already been run"

All previously-deployed initialization code was commented out / removed.

- **`NotarizationSerializer.sol`** — Commented out `rollingVoteIndex` (already ran). Added `// NOTE: removed as already ran.`
- **`NotaryTools.sol`** — Removed wBTC fix code (already ran). Replaced with `// Removed wBTC fix`
- **`UpgradeManager.sol`** — Commented out `rollingVoteIndex` (already ran). Added `// NOTE: Removed due to being deployed previously:`
- **`VerusCrossChainExport.sol`** — Commented out DAI vault setup (already ran). Added `// NOTE: removed as already ran.`

---

## 2026-06-25 — `46245b5` — "Updated contracts, hardened, extra checks, V8 SOLUTION Checked"

- **`NotarizationSerializer.sol`** — Added placeholder corrections for token accountancy (values `xxxxxxxxxx` — not yet ready for deploy):
  - `verusToERC20mapping[VETH].tokenIndex = xxxxxxxxxx` (ETH balance correction)
  - `verusToERC20mapping[wBTC].tokenIndex = xxxxxxxxxx` (wBTC balance correction)

---

## 2026-06-26 — `40d9cec` — "fix currency name"

- **`NotarizationSerializer.sol`** — Renamed `wBTC` → `tBTC` (wrong token; tBTC is the Verus-bridged Bitcoin token `iS8TfRPfVpKo5FVfSUzfHBQxo9KuzpnqLU`, not the Ethereum WBTC ERC20). Updated `tokenIndex` correction key accordingly.

---

## 2026-06-26 — `1ac4c06` — "add in vUSDC for correction"

- **`NotarizationSerializer.sol`** — Added vUSDC tokenIndex placeholder correction: `verusToERC20mapping[vUSDC].tokenIndex = xxxxxxxxxx`

---

## 2026-06-26 — `d841f03` — "correct vusdc address and checksum"

- **`NotarizationSerializer.sol`** — Fixed vUSDC immutable address from `0x67d6df2ccc766daffb1f36ccc9b8b5f0db5cd11b` → `0x1Bd15cDbf0B5B8c9CC361FFBaf6D76cc2CdfD667` (correct iaddress `i61cV2uicKSi1rSMQCBNQeSYC3UAi9GVzd` hex encoding)

---

## 2026-06-26 — `da4851d` — "Add updates from review"

- **`NotarizationSerializer.sol`** — Commented out the VETH/tBTC/vUSDC placeholder corrections (not ready to deploy with `xxxxxxxxxx` placeholder values; to be re-enabled once exact amounts are known)

---

## 2026-07-02 — `d0bc6a8` — "Add in Correction values for currencies"

- **`NotarizationSerializer.sol`** — Uncommented and populated currency balance corrections with real on-chain values:
  - `verusToERC20mapping[VETH].tokenIndex = (address(this).balance / SATS_TO_WEI_STD) + 118651397044`  — ETH: 1186.51397044 VRSC SATS outstanding in Verus
  - `verusToERC20mapping[tBTC].tokenIndex += 7603215250`  — tBTC: 76.03215250 VRSC SATS
  - `verusToERC20mapping[vUSDC].tokenIndex += 14765883679800`  — USDC: 147,658.83679800 VRSC SATS

---

## 2026-07-02 — `f8a8026` — "Correct last importtxid"

- **`NotarizationSerializer.sol`** — Multiple corrections:
  - Adjusted VETH correction: added `+ 556405765` (5.56405765 VRSC SATS in unclaimed fees)
  - Reset `lastImportInfo` to last known-good export state:
    - Verus source height end: **4070448**
    - Verus txid: `7712d764c1cfa4758faa3fa2c9bf96e1928d23c5658c4932e0a8d18879220a69` (txoutnum 0)
    - Hash transfers: `42412cbbb5222979a701e711ce864b0cda823e77b036a59a10d968c1eb9979f3`
  - Blocked 4 attacker/stuck CCE txids from re-submission via `processedTxids`:
    - `9b045a80c036fd737dec10fd4f6415887a05529ecb20c8189a2098d97dff6038` (height 4070982)
    - `97e1c41f0b2889a46ddfe519df5a0fbf24ec562fba73627f093290dd15e400f8` (height 4070995)
    - `7af0be458eaf3773f551c71b2cf6584add01b278fb55dfa5a50d549b802e7f1e` (height 4071014)
    - `f899e6984dc7c3d7737bbca5d87db3682de355743349d40396a5fc34b9f5a733` (height 4071017)

---

## 2026-07-02 — `4abbe59` — "Add initialize to stop revert"

New `initialize()` functions added to contracts that previously lacked one (to prevent delegate call reverts on upgrade):

- **`VerusProof.sol`** — Added `function initialize() external {}` (empty)
- **`ExportManager.sol`** — Added `function initialize() external {}` (empty)
- **`SubmitImports.sol`** — Collapsed empty function to `function initialize() external {}` (no-op change)
- **`VerusNotarizer.sol`** — Added `function initialize() external {}` (empty)

---

## 2026-07-02 — `bfa7e36` — "add autorevoke and allow access to the haltbridge commands direct"

- **`VerusCrossChainExport.sol`** — Added storageGlobal registrations so `haltBridge` and `resumeBridge` are callable via `Delegator.setVerusData()`:
  - `storageGlobal[keccak256("haltBridge")] = abi.encode(uint(ContractType.VerusNotaryTools))`
  - `storageGlobal[keccak256("resumeBridge")] = abi.encode(uint(ContractType.VerusNotaryTools))`

---

## 2026-07-09 — Reset to empty — "reset to empty 9-July-26"

All `initialize()` functions across all contracts reset to `function initialize() external {}`.

Previous active content archived above. Contracts reset:

| Contract | Previous content summary |
|---|---|
| `NotarizationSerializer.sol` | Currency tokenIndex corrections (VETH/tBTC/vUSDC), lastImportInfo reset, 4× processedTxids blocked |
| `NotaryTools.sol` | `// Removed wBTC fix` comment |
| `UpgradeManager.sol` | Commented-out rollingVoteIndex |
| `VerusCrossChainExport.sol` | haltBridge/resumeBridge storageGlobal registrations |
| `VerusSerializer.sol` | Empty (whitespace only) |
| `CreateExports.sol` | Commented-out DAI DSR correction note |
| `SubmitImports.sol` | Already empty `{}` |
| `TokenManager.sol` | Empty (whitespace only) |
| `VerusProof.sol` | Already empty `{}` |
| `ExportManager.sol` | Already empty `{}` |
| `VerusNotarizer.sol` | Already empty `{}` |
