// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
pragma abicoder v2;

import "./VerusObjects.sol";
import "./VerusConstants.sol";
import "./InternalCall.sol";
import "../Storage/StorageMaster.sol";
import "../VerusBridge/PendingImports.sol";
import "../VerusBridge/ExportManager.sol";

/// @dev TEST ONLY. Installed in a spare slot with Delegator.replacecontract, its initialize() runs in the Delegator's
///      storage and calls each internal-only logic function the way a stray setVerusData route would: by delegatecall,
///      with no flow active. The same call is then repeated with every flow bit set, as the control showing that the
///      flow guard is what refused the first call. Results are stored as abi.encode(bool success) at
///      storageGlobal[keccak256("mock.internal." ++ name)] and storageGlobal[keccak256("mock.internal." ++ name ++ ".withFlow")].
///      The control calls change state (they queue imports, record a token, append an export), so run it in a
///      snapshot. Never deploy to production.
contract MockInternalCaller is VerusStorage {

    address immutable VETH;

    constructor(address vETH) {
        VETH = vETH;
    }

    function _record(string memory name, bool success) private {
        storageGlobal[keccak256(abi.encodePacked("mock.internal.", name))] = abi.encode(success);
    }

    function _tryBoth(string memory name, uint256 slot, bytes memory callData) private {
        (bool success,) = contracts[slot].delegatecall(callData);
        _record(name, success);

        uint256 previous = InternalCall.enter(claimableFees, type(uint256).max);
        (success,) = contracts[slot].delegatecall(callData);
        InternalCall.exit(claimableFees, previous);
        _record(string(abi.encodePacked(name, ".withFlow")), success);
    }

    function initialize() external {
        _importFunctions();
        _queueFunction();
        _exportFunctions();
        _daiFunctions();
    }

    function _importFunctions() private {
        uint176[3] memory exporters;
        address someAddress = address(0x1234);
        _tryBoth("processTransactions", uint(VerusConstants.ContractType.TokenManager),
            abi.encodeWithSignature("processTransactions(bytes,uint128,bytes32,uint176[3])", "", uint128(0), bytes32(uint256(1)), exporters));
        _tryBoth("recordToken", uint(VerusConstants.ContractType.TokenManager),
            abi.encodeWithSignature("recordToken(address,address,string,string,uint8,uint256)", someAddress, someAddress, "X", "X", uint8(1), uint256(0)));
        _tryBoth("launchContractTokens", uint(VerusConstants.ContractType.VerusNotaryTools),
            abi.encodeWithSignature("launchContractTokens(bytes)", abi.encode(new VerusObjects.setupToken[](0))));
        _tryBoth("executePendingImport", uint(VerusConstants.ContractType.Imports),
            abi.encodeWithSignature("executePendingImport(bytes32)", bytes32(uint256(3))));
        _tryBoth("payOutImport", uint(VerusConstants.ContractType.Imports),
            abi.encodeWithSignature("payOutImport(address,address,uint64)", someAddress, VETH, uint64(0)));
        _tryBoth("payRefundOnETH", uint(VerusConstants.ContractType.Imports),
            abi.encodeWithSignature("payRefundOnETH(address,address,uint64)", someAddress, VETH, uint64(0)));
        _tryBoth("sendCurrencyToETHAddress", uint(VerusConstants.ContractType.ExportManager),
            abi.encodeWithSignature("sendCurrencyToETHAddress(address,address,uint256,uint32,uint256)", someAddress, someAddress, uint256(0), uint32(0), uint256(0)));
    }

    function _queueFunction() private {
        uint176[3] memory exporters;
        VerusObjects.PackedSend[] memory sends;
        VerusObjects.PackedCurrencyLaunch[] memory launches;
        bytes memory callData = abi.encodeWithSelector(PendingImports.queuePendingImport.selector,
            bytes32(uint256(2)), uint32(0), bytes32(0), uint32(0), uint128(0), sends, launches, uint64(0), exporters);
        _tryBoth("queuePendingImport", uint(VerusConstants.ContractType.PendingImports), callData);
    }

    function _exportFunctions() private {
        VerusObjects.CReserveTransfer memory transfer;
        VerusObjects.CReserveTransfer[] memory transfers = new VerusObjects.CReserveTransfer[](1);
        _tryBoth("externalCreateExportCallPayable", uint(VerusConstants.ContractType.CreateExport),
            abi.encodeWithSignature("externalCreateExportCallPayable(bytes)", abi.encode(transfer, false)));
        _tryBoth("externalCreateExportCall", uint(VerusConstants.ContractType.CreateExport),
            abi.encodeWithSignature("externalCreateExportCall(bytes)", abi.encode(transfer, false)));
        _tryBoth("checkExport", uint(VerusConstants.ContractType.ExportManager),
            abi.encodeWithSelector(ExportManager.checkExport.selector, transfer));
        // generateCCE has no flow: it refuses any delegatecall, with or without one.
        _tryBoth("generateCCE", uint(VerusConstants.ContractType.VerusCrossChainExport),
            abi.encodeWithSignature("generateCCE(bytes)",
                abi.encode(transfers, false, uint64(0), uint64(0), contracts[uint(VerusConstants.ContractType.VerusSerializer)])));
    }

    function _daiFunctions() private {
        _tryBoth("join", uint(VerusConstants.ContractType.VerusCrossChainExport),
            abi.encodeWithSignature("join(uint256)", uint256(0)));
        _tryBoth("exit", uint(VerusConstants.ContractType.VerusCrossChainExport),
            abi.encodeWithSignature("exit(address,uint256)", address(0x1234), uint256(0)));
        _tryBoth("daiBalance", uint(VerusConstants.ContractType.VerusCrossChainExport),
            abi.encodeWithSignature("daiBalance()"));
    }
}
