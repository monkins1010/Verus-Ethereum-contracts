// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusConstants.sol";
import "../Storage/StorageMaster.sol";

/**
 * @title NotarizationSerializer
 * @dev Clean deserializer for Verus CPBaaSNotarization binary format.
 *      Replaces the old assembly-heavy implementation with the explicit field
 *      parsers from NotarizationDeserializer.sol.
 *
 *      Called via delegatecall("deserializeNotarization(bytes)") from
 *      VerusNotarizer.checkNotarization.  All storage side-effects
 *      (castVote, claimableFees, bridgeConverterActive) are handled by the
 *      caller; this contract is a pure parser that returns the 7 values
 *      VerusNotarizer needs.
 *
 *      Inherits VerusStorage so the delegatecall storage layout is preserved.
 */
contract NotarizationSerializer is VerusStorage {

    address immutable VETH;
    address immutable BRIDGE;
    address immutable VERUS;
    address immutable DAI;
    address immutable MKR;

    constructor(address vETH, address Bridge, address Verus, address Dai, address Mkr) {
        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
        DAI = Dai;
        MKR = Mkr;
    }

    /// @notice No-op required by Delegator.replacecontract upgrade flow.
    function initialize() external {}

    // ── Notarization flags ─────────────────────────────────────────────────
    uint32 private constant FLAG_START_NOTARIZATION = 0x004;
    uint32 private constant FLAG_LAUNCH_CONFIRMED   = 0x008;
    uint32 private constant FLAG_LAUNCH_COMPLETE    = 0x100;
    uint32 private constant FLAG_CONTRACT_UPGRADE   = 0x200;
    uint32 private constant REQUIRED_FLAGS =
        FLAG_START_NOTARIZATION | FLAG_LAUNCH_CONFIRMED | FLAG_LAUNCH_COMPLETE;
    uint32 private constant ALLOWED_FLAGS =
        REQUIRED_FLAGS | FLAG_CONTRACT_UPGRADE;

    // ── CTransferDestination flags ─────────────────────────────────────────
    uint8 private constant DEST_FLAG_GATEWAY = 0x80;
    uint8 private constant DEST_FLAG_AUX     = 0x40;

    // ── CProofRoot types ───────────────────────────────────────────────────
    uint16 private constant PROOF_TYPE_PBAAS = 1;
    uint16 private constant PROOF_TYPE_ETH   = 2;

    // ── Fixed byte widths ──────────────────────────────────────────────────
    uint32 private constant SZ_U160 = 20;
    uint32 private constant SZ_U256 = 32;
    uint32 private constant SZ_U32  = 4;
    uint32 private constant SZ_U64  = 8;

    // ── Version constants ──────────────────────────────────────────────────
    uint64 private constant VERSION_PBAAS_MAINNET = 2;

    // ── Proposer packing ──────────────────────────────────────────────────
    // Offset of the vote address inside the first auxDest sub-vector.
    uint32 private constant AUX_VOTE_ADDR_OFFSET = 1;
    // Minimum sub-vector length that contains a valid vote address.
    uint32 private constant AUX_VOTE_MIN_LEN = 21;

    // ── CCurrencyState flags ───────────────────────────────────────────────
    uint16 private constant CS_FLAG_FRACTIONAL      = 0x001;
    uint16 private constant CS_FLAG_REFUNDING       = 0x004;
    uint16 private constant CS_FLAG_LAUNCH_CONFIRMED = 0x010;
    uint16 private constant CS_FLAG_LAUNCH_COMPLETE  = 0x020;
    // Bridge is launched when FRACTIONAL + LAUNCH_CONFIRMED + LAUNCH_COMPLETE
    // are all set and REFUNDING is clear.
    uint16 private constant CS_LAUNCH_CHECK_MASK =
        CS_FLAG_FRACTIONAL | CS_FLAG_REFUNDING |
        CS_FLAG_LAUNCH_CONFIRMED | CS_FLAG_LAUNCH_COMPLETE;
    uint16 private constant CS_LAUNCH_REQUIRED =
        CS_FLAG_FRACTIONAL | CS_FLAG_LAUNCH_CONFIRMED | CS_FLAG_LAUNCH_COMPLETE;

    // ══════════════════════════════════════════════════════════════════════
    //  External entry point
    //  Called via delegatecall as "deserializeNotarization(bytes)" from
    //  VerusNotarizer. Forwards to the internal parser with offset = 0.
    // ══════════════════════════════════════════════════════════════════════

    function deserializeNotarization(bytes memory notarization)
        external view
        returns (bytes32 proposerAndLaunched,
                 bytes32 prevnotarizationtxid,
                 bytes32 hashprevcrossnotarization,
                 bytes32 stateRoot,
                 uint32  height,
                 address votetxid,
                 uint256 reserves)
    {
        return _deserializeNotarization(notarization, 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Internal parser
    // ══════════════════════════════════════════════════════════════════════

    function _deserializeNotarization(bytes memory data, uint32 offset)
        internal view
        returns (bytes32 proposerAndLaunched,
                 bytes32 prevnotarizationtxid,
                 bytes32 hashprevcrossnotarization,
                 bytes32 stateRoot,
                 uint32  height,
                 address votetxid,
                 uint256 reserves)
    {
        uint32 pos = offset;

        // ── version ───────────────────────────────────────────────────────
        uint64 version;
        (version, pos) = _readVarint(data, pos);
        require(version == VERSION_PBAAS_MAINNET, "unsupported notarization version");

        // ── flags ─────────────────────────────────────────────────────────
        uint64 flags;
        (flags, pos) = _readVarint(data, pos);
        require(
            (uint32(flags) & REQUIRED_FLAGS) == REQUIRED_FLAGS &&
            (uint32(flags) & ~ALLOWED_FLAGS) == 0,
            "invalid notarization flags"
        );

        // ── proposer (CTransferDestination) ───────────────────────────────
        (proposerAndLaunched, votetxid, pos) = _readTransferDestination(data, pos);

        // ── currencyID (uint160) – validate it is VETH ────────────────────
        _checkBounds(data, pos, SZ_U160);
        address currencyId;
        assembly {
            currencyId := shr(96, mload(add(add(data, 0x20), pos)))
        }
        require(currencyId == VETH, "invalid notarization currencyid");
        pos += SZ_U160;

        // ── main CCoinbaseCurrencyState ───────────────────────────────────
        pos = _skipCoinbaseCurrencyState(data, pos);

        // ── notarizationHeight (uint32 LE) – skip ─────────────────────────
        pos += SZ_U32;

        // ── prevNotarizationTxId (uint256) ────────────────────────────────
        prevnotarizationtxid = _readBytes32(data, pos);
        pos += SZ_U256;

        // ── prevNotarizationOut (uint32 LE) – skip ────────────────────────
        pos += SZ_U32;

        // ── hashPrevCrossNotarization (uint256) ───────────────────────────
        hashprevcrossnotarization = _readBytes32(data, pos);
        pos += SZ_U256;

        // ── prevHeight (uint32 LE) – skip ─────────────────────────────────
        pos += SZ_U32;

        // ── currencyStates vector ─────────────────────────────────────────
        // Also extracts reserves and detects bridge launch.
        bool launched;
        (pos, reserves, launched) = _skipCurrencyStatesVector(data, pos);

        // Pack bridgeConverterLaunched flag at bit 176 of proposerAndLaunched.
        // VerusNotarizer gates activation on !bridgeConverterActive, so we pack
        // unconditionally when detected and let the caller decide.
        if (launched) {
            proposerAndLaunched |= bytes32(uint256(1) << VerusConstants.UINT176_BITS_SIZE);
        }

        // ── proofRoots vector ─────────────────────────────────────────────
        (stateRoot, height) = _readProofRoots(data, pos);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Variable-length integer readers
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @dev Read a Verus/Bitcoin varint from `data[pos]`.
     *      Each byte contributes 7 bits; high bit set means more follows.
     */
    function _readVarint(bytes memory data, uint32 pos)
        internal pure returns (uint64 v, uint32 newPos)
    {
        for (uint32 i = 0; i < 10; i++) {
            _checkBounds(data, pos + i, 1);
            uint8 b;
            assembly {
                b := byte(0, mload(add(add(data, 0x20), add(pos, i))))
            }
            require(v <= type(uint64).max >> 7);
            v = uint64((v << 7) | (b & 0x7f));
            if (b & 0x80 != 0x80) {
                return (v, pos + i + 1);
            }
            v++;
        }
        revert("invalid varint");
    }

    /**
     * @dev Read a Bitcoin compact-size integer (little-endian).
     *      <253 → 1 byte   253+2LE → 3 bytes   254+4LE → 5 bytes
     */
    function _readCompactSize(bytes memory data, uint32 pos)
        internal pure returns (uint64 v, uint32 newPos)
    {
        _checkBounds(data, pos, 1);
        uint8 first;
        assembly {
            first := byte(0, mload(add(add(data, 0x20), pos)))
        }
        newPos = pos + 1;

        if (first < 253) {
            return (first, newPos);
        }
        if (first == 253) {
            _checkBounds(data, newPos, 2);
            uint8 b0; uint8 b1;
            assembly {
                b0 := byte(0, mload(add(add(data, 0x20), newPos)))
                b1 := byte(0, mload(add(add(data, 0x20), add(newPos, 1))))
            }
            return (uint64(b0) | (uint64(b1) << 8), newPos + 2);
        }
        if (first == 254) {
            _checkBounds(data, newPos, 4);
            uint8 b0; uint8 b1; uint8 b2; uint8 b3;
            assembly {
                b0 := byte(0, mload(add(add(data, 0x20), newPos)))
                b1 := byte(0, mload(add(add(data, 0x20), add(newPos, 1))))
                b2 := byte(0, mload(add(add(data, 0x20), add(newPos, 2))))
                b3 := byte(0, mload(add(add(data, 0x20), add(newPos, 3))))
            }
            return (
                uint64(b0) | (uint64(b1) << 8) | (uint64(b2) << 16) | (uint64(b3) << 24),
                newPos + 4
            );
        }
        revert("compact-size 0xff not supported");
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Primitive readers
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Single revert covering all out-of-bounds reads in this contract.
    function _checkBounds(bytes memory data, uint32 pos, uint32 n) private pure {
        require(uint256(pos) + n <= data.length, "read past end");
    }

    function _readBytes32(bytes memory data, uint32 pos)
        internal pure returns (bytes32 result)
    {
        _checkBounds(data, pos, 32);
        assembly {
            result := mload(add(add(data, 0x20), pos))
        }
    }

    function _readUint32LE(bytes memory data, uint32 pos)
        internal pure returns (uint32 result)
    {
        _checkBounds(data, pos, 4);
        uint8 b0; uint8 b1; uint8 b2; uint8 b3;
        assembly {
            b0 := byte(0, mload(add(add(data, 0x20), pos)))
            b1 := byte(0, mload(add(add(data, 0x20), add(pos, 1))))
            b2 := byte(0, mload(add(add(data, 0x20), add(pos, 2))))
            b3 := byte(0, mload(add(add(data, 0x20), add(pos, 3))))
        }
        result = uint32(b0) | (uint32(b1) << 8) | (uint32(b2) << 16) | (uint32(b3) << 24);
    }

    function _swapUint64(uint64 v) private pure returns (uint64) {
        v = ((v & 0xFF00FF00FF00FF00) >> 8)  | ((v & 0x00FF00FF00FF00FF) << 8);
        v = ((v & 0xFFFF0000FFFF0000) >> 16) | ((v & 0x0000FFFF0000FFFF) << 16);
        return (v >> 32) | (v << 32);
    }

    function _readUint64LE(bytes memory data, uint32 pos)
        internal pure returns (uint64 result)
    {
        _checkBounds(data, pos, 8);
        assembly {
            result := shr(192, mload(add(add(data, 0x20), pos)))
        }
        result = _swapUint64(result);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  CTransferDestination
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @dev Read a CTransferDestination.
     *      proposer: type(1)+destLen(1)+address(20) packed into lower 176 bits,
     *                type-flag nibble cleared. Zero when destLen != 20.
     *      votetxid: 20-byte address at byte 1 of the first auxDest sub-vector.
     */
    function _readTransferDestination(bytes memory data, uint32 pos)
        internal pure
        returns (bytes32 proposer, address votetxid, uint32 newPos)
    {
        _checkBounds(data, pos, 1);
        uint8 destType;
        assembly {
            destType := byte(0, mload(add(add(data, 0x20), pos)))
        }
        uint32 typePos = pos;
        pos++;

        uint64 destLen;
        (destLen, pos) = _readCompactSize(data, pos);

        if (destLen == 20) {
            assembly {
                let p := add(add(data, 0x20), typePos)
                proposer := shr(80, mload(p))
                proposer := and(proposer, 0x0fffffffffffffffffffffffffffffffffffffffffff)
            }
        }
        pos += uint32(destLen);

        // Optional gateway: gatewayID(20) + gatewayCode(20) + fees(8) = 48 bytes
        if (destType & DEST_FLAG_GATEWAY != 0) {
            pos += 48;
        }

        // Optional auxDests: vec<vec<uint8>>
        if (destType & DEST_FLAG_AUX != 0) {
            uint64 numAux;
            (numAux, pos) = _readCompactSize(data, pos);
            for (uint64 i = 0; i < numAux; i++) {
                uint64 auxLen;
                (auxLen, pos) = _readCompactSize(data, pos);
                if (i == 0 && auxLen >= AUX_VOTE_MIN_LEN) {
                    _checkBounds(data, pos + 1, 20);
                    assembly {
                        votetxid := shr(96, mload(add(add(data, 0x20), add(pos, 1))))
                    }
                }
                pos += uint32(auxLen);
            }
        }

        newPos = pos;
    }

    // ══════════════════════════════════════════════════════════════════════
    //  CCurrencyState / CCoinbaseCurrencyState skippers
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @dev Advance past a CCurrencyState.
     *      Layout: version(2) + flags(2) + currencyID(20)
     *              + currencies(vec<u160>) + weights(vec<i32>) + reserves(vec<i64>)
     *              + varint(initialSupply) + varint(emitted) + varint(supply)
     */
    function _skipCurrencyState(bytes memory data, uint32 pos)
        internal pure returns (uint32)
    {
        pos += 24; // version(2) + flags(2) + currencyID(20)

        uint64 n;
        (n, pos) = _readCompactSize(data, pos);
        pos += uint32(n) * SZ_U160;  // currencies

        (n, pos) = _readCompactSize(data, pos);
        pos += uint32(n) * SZ_U32;   // weights

        (n, pos) = _readCompactSize(data, pos);
        pos += uint32(n) * SZ_U64;   // reserves

        (, pos) = _readVarint(data, pos); // initialSupply
        (, pos) = _readVarint(data, pos); // emitted
        (, pos) = _readVarint(data, pos); // supply

        return pos;
    }

    /**
     * @dev Advance past a CCoinbaseCurrencyState (CCurrencyState + extra fields).
     *      Extra: primaryCurrencyOut(8)+preConvertedOut(8)+primaryCurrencyFees(8)
     *             +primaryCurrencyConversionFees(8) = 32 bytes fixed
     *             + reserveIn + primaryCurrencyIn + reserveOut + conversionPrice
     *             + viaConversionPrice + fees (6 × vec<i64>)
     *             + priorWeights (vec<i32>) + conversionFees (vec<i64>)
     */
    function _skipCoinbaseCurrencyState(bytes memory data, uint32 pos)
        internal pure returns (uint32)
    {
        pos = _skipCurrencyState(data, pos);
        pos += 4 * SZ_U64; // four fixed int64 fields

        uint64 n;
        for (uint8 i = 0; i < 6; i++) {
            (n, pos) = _readCompactSize(data, pos);
            pos += uint32(n) * SZ_U64;
        }
        (n, pos) = _readCompactSize(data, pos);
        pos += uint32(n) * SZ_U32;   // priorWeights
        (n, pos) = _readCompactSize(data, pos);
        pos += uint32(n) * SZ_U64;   // conversionFees

        return pos;
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Reserve extraction
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @dev Read packed reserve values from a fractional CCurrencyState.
     *      Maps VETH→slot0, DAI→slot1, VERUS→slot2, MKR→slot3.
     *      Each slot is a 64-bit LE value packed into the corresponding
     *      64-bit range of the returned uint256.
     *
     * @param currPos       Position of the currencies compact-size byte.
     * @param numCurrencies Value already read from currPos.
     */
    function _getReserves(bytes memory data, uint32 currPos, uint8 numCurrencies)
        internal view returns (uint256 packed)
    {
        uint8[4] memory currSlot;
        currSlot[0] = 0xff; currSlot[1] = 0xff;
        currSlot[2] = 0xff; currSlot[3] = 0xff;

        uint8 cap = numCurrencies < 4 ? numCurrencies : 4;
        _checkBounds(data, currPos + 1, uint32(cap) * SZ_U160);
        for (uint8 i = 0; i < cap; i++) {
            address currency;
            uint32 p = currPos + 1 + uint32(i) * 20;
            assembly {
                currency := shr(96, mload(add(add(data, 0x20), p)))
            }
            if      (currency == VETH)  currSlot[i] = 0;
            else if (currency == DAI)   currSlot[i] = 1;
            else if (currency == VERUS) currSlot[i] = 2;
            else if (currency == MKR)   currSlot[i] = 3;
        }

        // reservePos = currPos + 1(cs) + n*20(addrs) + 1(weights-cs) + n*4(weights) + 1(reserves-cs)
        //            = currPos + 3 + n*24
        uint32 reservePos = currPos + 3 + uint32(numCurrencies) * 24;

        for (uint8 i = 0; i < cap; i++) {
            if (currSlot[i] != 0xff) {
                uint64 reserve = _readUint64LE(data, reservePos + uint32(i) * 8);
                packed |= uint256(reserve) << (uint256(currSlot[i]) << 6);
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  currencyStates vector
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @dev Advance past the currencyStates vector.
     *      Also extracts packed reserves from the first fractional BRIDGE state
     *      and detects whether the bridge launch conditions are met.
     *
     *      Bridge launched when BRIDGE currencyState has:
     *        CS_FLAG_FRACTIONAL | CS_FLAG_LAUNCH_CONFIRMED | CS_FLAG_LAUNCH_COMPLETE
     *        all set, and CS_FLAG_REFUNDING clear.
     *
    *      Mainnet format: no prefix; currencyID is inside the struct.
     */
    function _skipCurrencyStatesVector(bytes memory data, uint32 pos)
        internal view returns (uint32 newPos, uint256 reserves, bool launched)
    {
        uint64 numStates;
        (numStates, pos) = _readCompactSize(data, pos);

        for (uint64 i = 0; i < numStates; i++) {
            _checkBounds(data, pos, 24); // version(2)+flags(2)+currencyID(20)
            uint16 csFlags;
            address currencyId;
            assembly {
                let b0 := byte(0, mload(add(add(data, 0x20), add(pos, 2))))
                let b1 := byte(0, mload(add(add(data, 0x20), add(pos, 3))))
                csFlags    := or(b0, shl(8, b1))
                currencyId := shr(96, mload(add(add(data, 0x20), add(pos, 4))))
            }

            if (currencyId == BRIDGE) {
                // Detect bridge launch: FRACTIONAL + LAUNCH_CONFIRMED + LAUNCH_COMPLETE set, REFUNDING clear.
                if (!launched &&
                    (csFlags & CS_LAUNCH_CHECK_MASK) == CS_LAUNCH_REQUIRED)
                {
                    launched = true;
                }

                // Extract reserves from the first fractional BRIDGE state.
                if (reserves == 0 && (csFlags & CS_FLAG_FRACTIONAL) != 0) {
                    uint32 csPos = pos + 24; // skip version(2)+flags(2)+currencyID(20)
                    _checkBounds(data, csPos, 1);
                    uint8 numCurrencies;
                    assembly {
                        numCurrencies := byte(0, mload(add(add(data, 0x20), csPos)))
                    }
                    reserves = _getReserves(data, csPos, numCurrencies);
                }
            }

            pos = _skipCoinbaseCurrencyState(data, pos);
        }
        newPos = pos;
    }

    // ══════════════════════════════════════════════════════════════════════
    //  proofRoots vector
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @dev Iterate the proofRoots vector; return stateRoot and height from the
     *      FIRST type-1 (PBaaS) proof root whose systemID == VERUS.
     *      Duplicate systemIDs are ignored (first-wins, matching C++ std::map).
     *
     *      CProofRoot layout:
     *        version(i16 LE) + type(i16 LE) + systemID(u160)
     *        + rootHeight(u32 LE) + stateRoot(u256) + blockHash(u256)
     *        + compactPower(u256) [+ gasPrice(i64 LE) when type==ETH]
     *
    *      Mainnet format: no prefix.
     */
    function _readProofRoots(bytes memory data, uint32 pos)
        internal view returns (bytes32 stateRoot, uint32 height)
    {
        uint64 numRoots;
        (numRoots, pos) = _readCompactSize(data, pos);
        bool found;

        for (uint64 i = 0; i < numRoots; i++) {
            _checkBounds(data, pos, 4); // version(2)+type(2)
            uint16 proofType;
            assembly {
                let b0 := byte(0, mload(add(add(data, 0x20), add(pos, 2))))
                let b1 := byte(0, mload(add(add(data, 0x20), add(pos, 3))))
                proofType := or(b0, shl(8, b1))
            }
            pos += 4; // version(2) + type(2)

            _checkBounds(data, pos, SZ_U160);
            address systemID;
            assembly {
                systemID := shr(96, mload(add(add(data, 0x20), pos)))
            }
            pos += SZ_U160;

            uint32 thisHeight = _readUint32LE(data, pos);
            pos += SZ_U32;

            bytes32 thisStateRoot = _readBytes32(data, pos);
            pos += SZ_U256;

            pos += SZ_U256; // blockHash
            pos += SZ_U256; // compactPower

            if (proofType == PROOF_TYPE_ETH) {
                pos += SZ_U64; // gasPrice
            }

            if (!found && proofType == PROOF_TYPE_PBAAS && systemID == VERUS) {
                stateRoot = thisStateRoot;
                height    = thisHeight;
                found     = true;
            }
        }
    }
}


