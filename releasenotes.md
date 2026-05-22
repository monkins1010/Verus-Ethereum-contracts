# Release Notes

## 22 May 2026

Source: `git diff` (working tree)

### `contracts/Libraries/VerusConstants.sol`

Snippet:
```solidity
uint8 constant FLAG_SUPPLEMENTAL = 8;
uint8 constant FLAG_DEST_GATEWAY_LENGTH = 48;
```

What it does:
- Adds a dedicated bit flag for supplemental transfers.
- Adds a shared constant for gateway payload length so parser skip logic stays consistent across contracts.

### `contracts/MMR/VerusProof.sol`

Snippet:
```solidity
uint32 constant CCE_COPTP_HEADERSIZE = 4 + 1;
uint32 constant CCE_SOURCE_SYSTEM_DELTA = 20;

assembly {
	let flags := and(mload(add(firstObj, nextOffset)), 0x0800)
	if gt(flags, 0) {
		revert(0, 0)
	}
	nextOffset := add(nextOffset, CCE_SOURCE_SYSTEM_DELTA)
}

if (tmpuint8 & VerusConstants.FLAG_DEST_GATEWAY == VerusConstants.FLAG_DEST_GATEWAY)
{
	nextOffset += VerusConstants.FLAG_DEST_GATEWAY_LENGTH;
}
```

What it does:
- Corrects CCE header offset handling before source/destination field validation.
- Rejects proofs where `FLAG_SUPPLEMENTAL` is present.
- Fixes destination parsing when gateway metadata is present by skipping an explicit gateway segment length.

### `contracts/VerusBridge/VerusSerializer.sol`

Snippet:
```solidity
uint32 constant TRANSFER_GATEWAYSKIP = 48;

else if (oneByte == 254) {
	offset += 3;
	uint32 fourByte;
	assembly { fourByte := mload(add(incoming, offset)) }
	return (serializeUint32(fourByte), offset + 3);
} else {
	offset += 7;
	uint64 eightByte;
	assembly { eightByte := mload(add(incoming, offset)) }
	return (serializeUint64(eightByte), offset + 7);
}
```

What it does:
- Fixes gateway skip math (`48` bytes) for destination parsing.
- Extends CompactSize/VarInt decoding to support `0xfe` (uint32) and `0xff` (uint64) encoded values.
- Reorders/clarifies offset advancement around destination, gateway, aux destination, reserve-to-reserve, and cross-system fields to prevent misaligned reads.

### `contracts/VerusNotarizer/NotarizationSerializer.sol`

Snippet:
```solidity
if (proposerType & VerusConstants.FLAG_DEST_GATEWAY == VerusConstants.FLAG_DEST_GATEWAY)
{
	nextOffset += VerusConstants.FLAG_DEST_GATEWAY_LENGTH;
}

else if (oneByte == 254)
{
	offset += 3;
	uint32 fourByte;
	assembly { fourByte := mload(add(incoming, offset)) }
	return VerusObjectsCommon.UintReader(offset + 3, serializeUint32(fourByte));
}
```

What it does:
- Aligns notarization proposer destination parsing with gateway-aware skip behavior.
- Adds larger CompactSize integer decoding support (uint32/uint64 paths), matching serializer behavior.

### `contracts/VerusNotarizer/VerusNotarizer.sol`

Snippet:
```solidity
proofs[bytes32(uint256(uint32(uint256(proposer >> FORKS_DATA_OFFSET_FOR_HEIGHT))))] =
	abi.encodePacked(
		stateRoot,
		uint32(uint256(notarizations[uint(forkPos)].proposerPacked) >> FORKS_DATA_OFFSET_FOR_HEIGHT)
	);
```

What it does:
- Writes a `proofs[height]` entry during fork notarization updates.
- Prevents empty-proof lookups when a forked notarization later becomes confirmed and the confirmed state root is queried by height.

### `test/deployed.js`

Snippet:
```javascript
const { proofinput } = reservetransfer;
// removed: invalidComponents

// "Test Votes" suite is commented out

it("Test a CCE with the supplementary flag set reverts", async () => {
  ...
  await contractInstance.methods.checkExportAndTransfers(mainInput, "0x00a37e...").call();
});
```

What it does:
- Removes unused `invalidComponents` fixture usage.
- Temporarily disables the vote-upgrade test block that depends on non-default/developer-only setup.
- Adds a regression test ensuring supplementary-flagged CCE input reverts as expected.

### `test/reservetransfer.ts`

Snippet:
```typescript
value_map -> valueMap
fee_currency_id -> feeCurrencyID
fee_amount -> feeAmount
transfer_destination -> transferDestination
destination_bytes -> destinationBytes
gateway_id -> gatewayID
aux_dests -> auxDests
dest_currency_id -> destCurrencyID
second_reserve_id -> secondReserveID
dest_system_id -> destSystemID
```

What it does:
- Updates test object field names to the current camelCase API expected by `verus-typescript-primitives`.
- Prevents silent serialization mismatches caused by stale snake_case keys.

---

## Release Notes Template (Use For Every Bug Fix / Fix / Upgrade)

~~~md
## DD Mon YYYY

Source: `git diff <range>`

### path/to/file.ext

Snippet:
```language
<important changed lines>
```

What it does:
- <behavioral change>
- <bug fixed / risk reduced>
~~~
