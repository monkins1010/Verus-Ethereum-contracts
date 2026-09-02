// SPDX-License-Identifier: MIT
// Import execution pipeline — handles everything that runs when a pending import is released.
// Called via delegatecall from PendingImports._executeImport.
//
// Functions moved here from:
//   SubmitImports  → executePendingImport, calulateGasFees, setClaimableFees, setClaimedFees, refund
//   TokenManager   → processTransactionsDecoded, launchToken, recordToken,
//                    importTransactions, sendCurrencyToETHAddress, convertFromVerusNumber

pragma solidity >=0.8.9;
pragma abicoder v2;

import "./Token.sol";
import "../Libraries/VerusConstants.sol";
import "../Libraries/VerusObjects.sol";
import "../Storage/StorageMaster.sol";
import "./VerusCrossChainExport.sol";
import {VerusSerializer} from "./VerusSerializer.sol";

interface IVerusToken {
    function supply() external view returns (uint256);
}

contract Imports is VerusStorage {

    // ── Immutables ──────────────────────────────────────────────────────────
    address immutable VETH;
    address immutable VERUS;
    uint256 immutable DEPLOYED_AT;
    uint256 constant THREE_YEARS = 3 * 365 days;

    // ── Constants (from SubmitImports) ──────────────────────────────────────
    uint32 constant FORKS_NOTARY_PROPOSER_POSITION = 96;
    uint32 constant TYPE_REFUND                    = 1;
    uint8  constant TYPE_REFUND_BYTES32_LOCATION   = 244;

    // Keys that match TokenManager storage.
    bytes32 constant PENDING_EXEC_DATA_PREFIX    = keccak256("pending.exec.data");
    bytes32 constant PENDING_EXEC_PARAMS_PREFIX  = keccak256("pending.exec.params");
    bytes32 constant IMPORTS_CONTRACT_INDEX_KEY  = keccak256("Imports.contract.index");

    constructor(address vETH, address verus) {
        VETH        = vETH;
        VERUS       = verus;
        DEPLOYED_AT = block.timestamp;
    }

    /// @notice No-op — array extension is handled by UpgradeManager.initialize().
    function initialize() external {}

    // ════════════════════════════════════════════════════════════════════════
    // ENTRY POINT
    // Called by PendingImports._executeImport via delegatecall.
    // Runs the full payout + fee-distribution pipeline for a released import.
    // ════════════════════════════════════════════════════════════════════════

    function executePendingImport(bytes32 importTxid) external {

        uint256 gasleftStart = gasleft();
        bytes memory refundsData;
        uint64 fees;
        uint176[] memory refundAddresses;

        {
            (refundsData, fees, refundAddresses) = processTransactionsDecoded(importTxid);
        }

        uint128 cceHeightsAndIndex;
        uint176[3] memory exporters;

        {
            bytes32 paramsKey = keccak256(abi.encodePacked(PENDING_EXEC_PARAMS_PREFIX, importTxid));
            (cceHeightsAndIndex, exporters) = abi.decode(storageGlobal[paramsKey], (uint128, uint176[3]));
            delete storageGlobal[paramsKey];
        }

        calulateGasFees(
            gasleftStart, fees, refundAddresses,
            uint32(cceHeightsAndIndex >> 32) - uint32(cceHeightsAndIndex),
            exporters
        );

        if (refundsData.length > 0) {
            refund(refundsData);
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // TOKEN PAYOUT  (moved from TokenManager)
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Reads the pre-decoded exec data stored by TokenManager.processTransactions,
    ///      launches any new currencies, and pays out all transfers.
    function processTransactionsDecoded(bytes32 importTxid)
        private
        returns (bytes memory refundsData, uint64 fees, uint176[] memory refundAddresses)
    {
        VerusObjects.PackedSend[] memory transfers;
        {
            bytes32 execKey = keccak256(abi.encodePacked(PENDING_EXEC_DATA_PREFIX, importTxid));
            VerusObjects.PackedCurrencyLaunch[] memory launchTxs;
            (transfers, launchTxs, fees) = abi.decode(
                storageGlobal[execKey],
                (VerusObjects.PackedSend[], VerusObjects.PackedCurrencyLaunch[], uint64)
            );
            delete storageGlobal[execKey];
            launchToken(launchTxs);
        }

        refundsData = importTransactions(transfers);

        {
            uint256 txCount = transfers.length;
            refundAddresses = new uint176[](txCount);
            for (uint256 i = 0; i < txCount; i++) {
                refundAddresses[i] = transfers[i].refundAddress;
            }
        }
    }

    // ── TOKEN LAUNCH / PAYOUT ────────────────────────────────────────────────
    // These functions delegate to ExportManager so the heavy ERC20/721/1155 send
    // logic and recordToken bytecode live there, keeping Imports.sol lean.

    /// @dev Registers any newly launched currencies via ExportManager.recordToken.
    function launchToken(VerusObjects.PackedCurrencyLaunch[] memory _tx) private {

        for (uint j = 0; j < _tx.length; j++) {
            if (verusToERC20mapping[_tx[j].iaddress].flags > 0 || _tx[j].iaddress == address(0))
                continue;

            VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).checkIAddress(_tx[j]);

            string memory outputName;

            if (_tx[j].flags &
                (VerusConstants.MAPPING_ETHEREUM_OWNED | VerusConstants.MAPPING_ERC1155_ERC_DEFINITION | VerusConstants.MAPPING_ERC1155_NFT_DEFINITION)
                    == VerusConstants.MAPPING_ETHEREUM_OWNED)
            {
                (bool success, bytes memory result) = _tx[j].ERCContract.call{gas: 30000}(abi.encodeWithSignature("name()"));
                if (success && result.length >= 64) {
                    uint256 offset;
                    uint256 strlen;
                    assembly {
                        offset := mload(add(result, 0x20))
                        strlen := mload(add(result, 0x40))
                    }
                    outputName = (offset == 0x20 && strlen <= result.length - 64)
                        ? abi.decode(result, (string))
                        : "...";
                } else {
                    outputName = "...";
                }
                outputName = string(abi.encodePacked("[", outputName, "] as "));
            }

            outputName = string(abi.encodePacked(outputName, _tx[j].name));

            if (_tx[j].parent != VERUS) {
                outputName = string(abi.encodePacked(outputName, ".", verusToERC20mapping[_tx[j].parent].name));
            }

            (bool ok,) = contracts[uint(VerusConstants.ContractType.TokenManager)].delegatecall(
                abi.encodeWithSignature(
                    "recordToken(address,address,string,string,uint8,uint256)",
                    _tx[j].iaddress, _tx[j].ERCContract, outputName, _tx[j].name, uint8(_tx[j].flags), _tx[j].tokenID
                )
            );
            require(ok);
        }
    }

    /// @dev Sends each transfer to its destination.
    ///      Simple ETH sends and Verus-NFT mints happen directly here;
    ///      ERC-20/721/1155 sends are delegated to ExportManager.sendCurrencyToETHAddress.
    function importTransactions(VerusObjects.PackedSend[] memory trans) private returns (bytes memory refundsData) {

        VerusObjects.mappedToken memory tempToken;

        for (uint256 i = 0; i < trans.length; i++) {

            uint64  sendAmount  = trans[i].amount;
            address destination = trans[i].destination;
            address currency    = trans[i].currency;
            tempToken = verusToERC20mapping[currency];
            uint32 result;

            if (currency == VETH) {
                (bool success, ) = destination.call{value: sendAmount * VerusConstants.SATS_TO_WEI_STD, gas: 100000}("");
                result = success ? 6 : 1; // SEND_SUCCESS_ETH : SEND_FAILED
            } else if (
                tempToken.flags & VerusConstants.MAPPING_ERC721_NFT_DEFINITION == VerusConstants.MAPPING_ERC721_NFT_DEFINITION &&
                tempToken.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED
            ) {
                VerusNft(tempToken.erc20ContractAddress).mint(currency, tempToken.name, destination);
                result = 0;
            } else {
                // Determine which ERC selector is needed, then delegatecall ExportManager.
                uint32 selector;
                if (tempToken.flags & VerusConstants.MAPPING_ERC20_DEFINITION == VerusConstants.MAPPING_ERC20_DEFINITION) {
                    selector = uint32(
                        tempToken.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED
                            ? Token.mint.selector : ERC20.transfer.selector
                    );
                } else if (tempToken.flags & VerusConstants.MAPPING_ERC721_NFT_DEFINITION == VerusConstants.MAPPING_ERC721_NFT_DEFINITION) {
                    selector = uint32(bytes4(0x23b872dd)); // IERC721.transferFrom selector
                } else if (
                    tempToken.flags & VerusConstants.MAPPING_ERC1155_NFT_DEFINITION == VerusConstants.MAPPING_ERC1155_NFT_DEFINITION ||
                    tempToken.flags & VerusConstants.MAPPING_ERC1155_ERC_DEFINITION == VerusConstants.MAPPING_ERC1155_ERC_DEFINITION
                ) {
                    selector = uint32(bytes4(0xf242432a)); // IERC1155.safeTransferFrom selector
                }

                if (selector != 0) {
                    (bool ok, bytes memory ret) = contracts[uint(VerusConstants.ContractType.ExportManager)].delegatecall(
                        abi.encodeWithSignature(
                            "sendCurrencyToETHAddress(address,address,uint256,uint32,uint256)",
                            tempToken.erc20ContractAddress, destination, sendAmount, selector, tempToken.tokenID
                        )
                    );
                    result = ok && ret.length > 0 ? abi.decode(ret, (uint8)) : 1; // 1 = SEND_FAILED
                }
            }

            if (result == 1 /* SEND_FAILED */ && sendAmount > 0) {
                refundsData = abi.encodePacked(refundsData, trans[i].refundAddress, sendAmount, currency);
            } else if (result == 2 /* SEND_SUCCESS */ || result == 6 /* SEND_SUCCESS_ETH */) {
                verusToERC20mapping[currency].tokenIndex -= sendAmount;
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // FEE DISTRIBUTION  (moved from SubmitImports)
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Calculates gas-cost-based fee distribution across notaries, exporters and bridge users.
    function calulateGasFees(
        uint256 gasStart,
        uint64 fees,
        uint176[] memory refundAddresses,
        uint256 blockWidth,
        uint176[3] memory exporters
    ) private {

        uint256 reimbursablePrice = block.basefee + VerusConstants.MAX_TIP;
        uint256 priceOfImports = uint256(
            (gasStart - gasleft()) +
            VerusConstants.GAS_BASE_COST_FOR_NOTARYS +
            (refundAddresses.length * VerusConstants.GAS_BASE_COST_FOR_REFUND_PAYOUTS)
        ) * reimbursablePrice;

        uint64 notaryFees = uint64(((priceOfImports * 14) / 10) / VerusConstants.SATS_TO_WEI_STD);

        if (fees > (notaryFees + (notaryFees >> 4))) {

            uint64 blockDivisor      = blockWidth > 1 ? 10 : 20;
            uint64 minTxesForRefund  = blockWidth > 1
                ? VerusConstants.MINIMUM_TRANSACTIONS_FOR_REFUNDS_HALF
                : VerusConstants.MINIMUM_TRANSACTIONS_FOR_REFUNDS;

            uint64 processorsFees;
            if (refundAddresses.length > minTxesForRefund) {
                processorsFees = fees - notaryFees;
                fees = notaryFees;

                uint64 feeRefunds = uint64(
                    (processorsFees / refundAddresses.length) * (refundAddresses.length - minTxesForRefund)
                );
                feeRefunds       = feeRefunds - (feeRefunds / blockDivisor);
                processorsFees   = processorsFees - feeRefunds;
                feeRefunds       = feeRefunds / uint64(refundAddresses.length);

                for (uint i = 0; i < refundAddresses.length; i++) {
                    bytes32 addr = bytes32(uint256(refundAddresses[i]));
                    if (addr != bytes32(0)) {
                        addr |= bytes32(uint256(TYPE_REFUND) << TYPE_REFUND_BYTES32_LOCATION);
                        refunds[addr][VETH] += feeRefunds;
                    } else {
                        processorsFees += feeRefunds;
                    }
                }
            } else {
                processorsFees = fees - notaryFees;
                fees = notaryFees;
            }

            setClaimableFees(fees, exporters, processorsFees);
        } else {
            setClaimableFees(fees, exporters, 0);
        }
    }

    /// @dev Distributes fees to the notary pool, proposer, and exporters/protocol.
    function setClaimableFees(uint64 notaryFees, uint176[3] memory exporters, uint64 processorsFees) private {

        uint64 feeShare = processorsFees / 3;
        claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL] += (notaryFees + feeShare);

        if (processorsFees > 0) {

            bytes memory proposerBytes = bestForks[0];
            uint176 proposer;
            require(proposerBytes.length >= FORKS_NOTARY_PROPOSER_POSITION + 22);
            assembly { proposer := mload(add(proposerBytes, FORKS_NOTARY_PROPOSER_POSITION)) }

            uint64 exporterTotal = processorsFees - (feeShare << 1);
            uint64 exporterHalf  = exporterTotal / 2;
            uint64 protocolShare = exporterTotal - exporterHalf;

            setClaimedFees(bytes32(uint256(proposer)), feeShare);
            setClaimedFees(bytes32(uint256(exporters[1])), exporterHalf);

            bool normalProtocolFeeRecipent = false;
            if (block.timestamp >= DEPLOYED_AT + THREE_YEARS) {
                (bool ok, bytes memory ret) = VerusConstants.VERUS_USAGE_CONTRACT.staticcall(
                    abi.encodeWithSelector(IVerusToken.supply.selector)
                );
                if (ok && ret.length >= 32) {
                    normalProtocolFeeRecipent = VerusConstants.VERUS_USAGE_CONTRACT.balance >= abi.decode(ret, (uint256));
                }
            }

            if (normalProtocolFeeRecipent) {
                setClaimedFees(bytes32(uint256(exporters[0])), protocolShare);
            } else {
                (bool success, ) = payable(VerusConstants.VERUS_USAGE_CONTRACT).call{value: protocolShare * VerusConstants.SATS_TO_WEI_STD}("");
                require(success);
                verusToERC20mapping[VETH].tokenIndex -= protocolShare;
            }
        }
    }

    function setClaimedFees(bytes32 _address, uint256 fees) private {
        claimableFees[_address] += fees;
    }

    /// @dev Stores failed-transfer refund amounts for later claim via SubmitImports.claimRefund.
    function refund(bytes memory refundAmount) private {

        if (refundAmount.length < 50) return;

        for (uint i = 0; i < refundAmount.length; i += 50) {
            uint176 verusAddress;
            uint64 amount;
            address currency;
            assembly {
                verusAddress := mload(add(add(refundAmount, 22), i))
                amount       := mload(add(add(refundAmount, 30), i))
                currency     := mload(add(add(refundAmount, 50), i))
            }
            bytes32 refundAddress = bytes32(uint256(verusAddress) | uint256(TYPE_REFUND) << TYPE_REFUND_BYTES32_LOCATION);
            refunds[refundAddress][currency] += amount;
        }
    }
}
