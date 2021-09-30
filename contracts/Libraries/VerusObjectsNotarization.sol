// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 < 0.9.0;
pragma experimental ABIEncoderV2;

import "./VerusObjectsCommon.sol";

library VerusObjectsNotarization {

     struct CProofRoot{
        int16 version;                        // to enable future data types with various functions
        int16 cprtype;                           // type of proof root
        address systemid;                       // system that can have things proven on it with this root
        uint32 rootheight;                    // height (or sequence) of the notarization we certify
        bytes32 stateroot;                      // latest MMR root of the notarization height
        bytes32 blockhash;                      // combination of block hash, block MMR root, and compact power (or external proxy) for the notarization height
        bytes32 compactpower;   
    }

    struct CurrencyStates {
        address currencyid;
        CCoinbaseCurrencyState currencystate;
    }

    struct ProofRoots {
        address currencyid;
        CProofRoot proofroot;
    }

    struct CCoinbaseCurrencyState {
        uint16 version;
        uint16 flags;
        address currencyid;
        uint160[] currencies;
        int32[] weights;
        int64[] reserves;
        int64 initialsupply;
        int64 emitted;
        int64 supply;
        int64 primarycurrencyout;
        int64 preconvertedout;
        int64 primarycurrencyfees;
        int64 primarycurrencyconversionfees;
        int64[] reservein;         // reserve currency converted to native
        int64[] primarycurrencyin;
        int64[] reserveout;        // output can have both normal and reserve output value, if non-0, this is spent by the required output transactions
        int64[] conversionprice;   // calculated price in reserve for all conversions * 100000000
        int64[] viaconversionprice; // the via conversion stage prices
        int64[] fees;              // fee values in native (or reserve if specified) coins for reserve transaction fees for the block
        int32[] priorweights;
        int64[] conversionfees;    // total of only conversion fees, which will accrue to the conversion transaction
    }

    struct CUTXORef {
        bytes32 hash;
        uint32 n;
    }

    struct CNodeData {
        string networkaddress;
        address nodeidentity;
    }

    struct CPBaaSNotarization {
        uint32 version;
        uint32 flags;
        VerusObjectsCommon.CTransferDestination proposer;
        address currencyid;
        CCoinbaseCurrencyState currencystate;
        uint32 notarizationheight;
        CUTXORef prevnotarization;
        bytes32 hashprevnotarization;
        uint32 prevheight;
        CurrencyStates[] currencystates;
        CProofRoot[] proofroots;
        CNodeData[] nodes;
    }

    //represents the output from the pbaas rpc
    struct Notarization {
        uint32 index;
        bytes32 txid;
        uint32 vout;
        CPBaaSNotarization notarization;
        CNodeData[] nodes;
    }

    struct CChainNotarizationData {
        uint32 version;
        Notarization[] notarizations;
        int32[][] forks; // chains that represent alternate branches from the last confirmed notarization
        int32 lastConfirmedHeight; // last confirmed notarization
        int32 bestChain; // index in forks of the chain, beginning with the last confirmed notarization, that has the most power
    }
}