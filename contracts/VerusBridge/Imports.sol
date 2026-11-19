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
import "../Libraries/InternalCall.sol";

interface IVerusToken {
    function supply() external view returns (uint256);
}

contract Imports is VerusStorage {

    // ── Immutables ──────────────────────────────────────────────────────────
    address immutable VETH;
    address immutable VERUS;
    uint256 immutable DEPLOYED_AT;
    address immutable SELF;
    uint256 constant THREE_YEARS = 3 * 365 days;

    // ── Constants (from SubmitImports) ──────────────────────────────────────
    uint32 constant FORKS_NOTARY_PROPOSER_POSITION = 96;
    uint32 constant TYPE_REFUND                    = 1;
    uint8  constant TYPE_REFUND_BYTES32_LOCATION   = 244;
    uint8  constant TYPE_BYTE_LOCATION_IN_UINT176  = 168;

    uint32 constant SEND_SUCCESS_NO_DEBIT = 0;
    uint32 constant SEND_FAILED = 1;
    uint32 constant SEND_SUCCESS = 2;
    uint32 constant SEND_SUCCESS_ETH = 6;
    uint256 constant ETH_PAYOUT_GAS_LIMIT = 100000;
    uint256 constant NFT_MINT_GAS_LIMIT = 150000;
    uint256 constant MAX_ERC_NAME_LENGTH = 64;
    // A release is one transaction, so its cost must stay bounded. A launch of a Verus-owned ERC-20 deploys a Token
    // (about 1.75M gas); four launches plus a full batch of payouts stay well inside the 16M gas a releasing vote
    // may use. verusd puts at most two currency definitions in one export. Launches beyond the cap are skipped:
    // the currency stays unmapped and its payouts refund.
    uint256 constant MAX_LAUNCHES_PER_IMPORT = 4;
    // Gas given to each launch and each payout, each run in its own call frame so that a failure there is local.
    // The caller must leave enough gas for the full amount: a releasing vote sent with too little gas reverts
    // instead of turning a payout into a refund or skipping a launch.
    uint256 constant LAUNCH_GAS = 3000000;
    uint256 constant PAYOUT_GAS = 400000;
    uint256 constant PROTOCOL_SHARE_GAS = 50000;
    bytes4 constant ERC721_SEND_SELECTOR = bytes4(0x23b872dd);
    bytes4 constant ERC1155_SEND_SELECTOR = bytes4(0xf242432a);

    // Keys that match TokenManager storage.
    bytes32 constant PENDING_EXEC_DATA_PREFIX    = keccak256("pending.exec.data");
    bytes32 constant PENDING_EXEC_PARAMS_PREFIX  = keccak256("pending.exec.params");
    bytes32 constant IMPORTS_CONTRACT_INDEX_KEY  = keccak256("Imports.contract.index");

    constructor(address vETH, address verus) {
        VETH        = vETH;
        VERUS       = verus;
        DEPLOYED_AT = block.timestamp;
        SELF        = address(this);
    }

    /// @notice No-op — array extension is handled by UpgradeManager.initialize().
    function initialize() external {}

    // ════════════════════════════════════════════════════════════════════════
    // ENTRY POINT
    // Called by PendingImports._executeImport via delegatecall.
    // Runs the full payout + fee-distribution pipeline for a released import.
    // ════════════════════════════════════════════════════════════════════════

    function executePendingImport(bytes32 importTxid) external {

        InternalCall.only(claimableFees, InternalCall.EXECUTE_IMPORT);
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

        // Export height range; an end below the start (only a malformed export) counts as a single block
        // rather than reverting the release.
        uint32 startHeight = uint32(cceHeightsAndIndex);
        uint32 endHeight = uint32(cceHeightsAndIndex >> 32);

        calulateGasFees(
            gasleftStart, fees, refundAddresses,
            endHeight > startHeight ? endHeight - startHeight : 0,
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
            if (launchTxs.length > 0) {
                launchToken(launchTxs);
            }
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

    /// @dev Registers any newly launched currencies via TokenManager.recordToken.
    ///      A launch that is skipped (mismatched name, over the cap) or fails leaves the currency unmapped; its
    ///      payouts then refund via the "not launched on ETH yet" branch. None of them reverts the release.
    function launchToken(VerusObjects.PackedCurrencyLaunch[] memory _tx) private {

        uint256 launched;

        for (uint j = 0; j < _tx.length; j++) {
            if (verusToERC20mapping[_tx[j].iaddress].flags > 0 || _tx[j].iaddress == address(0))
                continue;

            if (!VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]).checkIAddress(_tx[j]))
                continue;

            if (launched == MAX_LAUNCHES_PER_IMPORT)
                break;
            launched++;

            // Too little gas reverts the whole release, so a sender cannot make a launch fail on purpose.
            require(gasleft() > LAUNCH_GAS + LAUNCH_GAS / 32);

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
                    // a long name() would make the launch, and its whole import, too costly to release
                    outputName = (offset == 0x20 && strlen <= MAX_ERC_NAME_LENGTH && strlen <= result.length - 64)
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

            // A failed launch is undone and skipped (its result is deliberately ignored).
            contracts[uint(VerusConstants.ContractType.TokenManager)].delegatecall{gas: LAUNCH_GAS}(
                abi.encodeWithSignature(
                    "recordToken(address,address,string,string,uint8,uint256)",
                    _tx[j].iaddress, _tx[j].ERCContract, outputName, _tx[j].name, uint8(_tx[j].flags), _tx[j].tokenID
                )
            );
        }
    }

    /// @dev Sends each transfer to its destination.
    ///      Simple ETH sends and Verus-NFT mints happen directly here;
    ///      ERC-20/721/1155 sends are delegated to ExportManager.sendCurrencyToETHAddress.
    function importTransactions(VerusObjects.PackedSend[] memory trans) private returns (bytes memory refundsData) {

        for (uint256 i = 0; i < trans.length; i++) {

            // Currency-launch marker entries carry no payout (amount 0, destination zero); skip them.
            if (trans[i].launchTxIndexPlusOne > 0) {
                continue;
            }

            uint64 sendAmount = trans[i].amount;

            // Each payout runs in its own call frame (payOutImport), so anything that reverts in it, the send or
            // the custody debit, undoes that payout alone and turns it into a refund instead of reverting the release.
            // Too little gas reverts the whole release, so a sender cannot make a payout fail on purpose.
            require(gasleft() > PAYOUT_GAS + PAYOUT_GAS / 32);
            (bool paid,) = SELF.delegatecall{gas: PAYOUT_GAS}(
                abi.encodeWithSelector(this.payOutImport.selector, trans[i].destination, trans[i].currency, sendAmount)
            );

            if (!paid && sendAmount > 0) {
                refundsData = abi.encodePacked(refundsData, trans[i].refundAddress, sendAmount, trans[i].currency);
            }
        }
    }

    /// @notice One import payout. Called only by importTransactions (via delegatecall to this contract) during a
    ///         release; reverts unless the payout succeeded and custody was debited.
    function payOutImport(address destination, address currency, uint64 amount) external {
        InternalCall.only(claimableFees, InternalCall.EXECUTE_IMPORT);
        require(_payOut(destination, currency, amount, ETH_PAYOUT_GAS_LIMIT) != SEND_FAILED);
    }

    /// @notice Pays a stored refund out on Ethereum to its DEST_ETH refund address.
    ///         Called via delegatecall from SubmitImports.claimRefund, which has already removed the refund
    ///         entry; reverts if the payout fails so the refund stays claimable.
    function payRefundOnETH(address destination, address currency, uint64 amount) external {
        InternalCall.only(claimableFees, InternalCall.CLAIM_REFUND);
        require(_payOut(destination, currency, amount, gasleft()) != SEND_FAILED, "Refund payout failed");
    }

    /// @dev Sends one payout to an Ethereum address and debits custody on success.
    ///      ethGas is the gas forwarded to a plain vETH send.
    function _payOut(address destination, address currency, uint64 sendAmount, uint256 ethGas) private returns (uint32 result) {

        VerusObjects.mappedToken memory tempToken = verusToERC20mapping[currency];

        if (currency == VETH) {
            (bool success, ) = destination.call{value: sendAmount * VerusConstants.SATS_TO_WEI_STD, gas: ethGas}("");
            result = success ? SEND_SUCCESS_ETH : SEND_FAILED;
        } else if (
            tempToken.flags & VerusConstants.MAPPING_ERC721_NFT_DEFINITION == VerusConstants.MAPPING_ERC721_NFT_DEFINITION &&
            tempToken.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED
        ) {
            (bool success, ) = tempToken.erc20ContractAddress.call{gas: NFT_MINT_GAS_LIMIT}(
                abi.encodeWithSelector(VerusNft.mint.selector, currency, tempToken.name, destination)
            );
            result = success ? SEND_SUCCESS_NO_DEBIT : SEND_FAILED;
        } else {
            // Determine which ERC selector is needed, then delegatecall ExportManager.
            uint32 selector;
            if (tempToken.flags & VerusConstants.MAPPING_ERC20_DEFINITION == VerusConstants.MAPPING_ERC20_DEFINITION) {
                selector = uint32(
                    tempToken.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED
                        ? Token.mint.selector : ERC20.transfer.selector
                );
            } else if (tempToken.flags & VerusConstants.MAPPING_ERC721_NFT_DEFINITION == VerusConstants.MAPPING_ERC721_NFT_DEFINITION) {
                selector = uint32(ERC721_SEND_SELECTOR);
            } else if (
                tempToken.flags & VerusConstants.MAPPING_ERC1155_NFT_DEFINITION == VerusConstants.MAPPING_ERC1155_NFT_DEFINITION ||
                tempToken.flags & VerusConstants.MAPPING_ERC1155_ERC_DEFINITION == VerusConstants.MAPPING_ERC1155_ERC_DEFINITION
            ) {
                selector = uint32(ERC1155_SEND_SELECTOR);
            }

            if (selector != 0) {
                (bool ok, bytes memory ret) = contracts[uint(VerusConstants.ContractType.ExportManager)].delegatecall(
                    abi.encodeWithSignature(
                        "sendCurrencyToETHAddress(address,address,uint256,uint32,uint256)",
                        tempToken.erc20ContractAddress, destination, sendAmount, selector, tempToken.tokenID
                    )
                );
                result = ok && ret.length > 0 ? abi.decode(ret, (uint8)) : SEND_FAILED;
            } else {
                // currency not launched on ETH yet, refund rather than drop the payment
                result = SEND_FAILED;
            }
        }

        if (result == SEND_SUCCESS ||
            (result == SEND_SUCCESS_ETH && destination != address(this))) {
            verusToERC20mapping[currency].tokenIndex -= sendAmount;
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
                    // vETH fee refunds go only to keys claimRefund pays vETH to: PKH and ID (sent back to Verus) and
                    // ETH (paid on Ethereum). A P2SH key is paid only VRSC, and the zero key not at all, so those
                    // shares go to the processors' fees instead of being stranded.
                    uint8 keyType = uint8(refundAddresses[i] >> TYPE_BYTE_LOCATION_IN_UINT176);
                    if (keyType == VerusConstants.DEST_PKH || keyType == VerusConstants.DEST_ID || keyType == VerusConstants.DEST_ETH) {
                        bytes32 addr = bytes32(uint256(refundAddresses[i]) | uint256(TYPE_REFUND) << TYPE_REFUND_BYTES32_LOCATION);
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
            // A confirmed-notarization record too short to hold the proposer leaves it zero (its share then goes to
            // the notary pool) rather than reverting the release.
            if (proposerBytes.length >= FORKS_NOTARY_PROPOSER_POSITION + 22) {
                assembly { proposer := and(mload(add(proposerBytes, FORKS_NOTARY_PROPOSER_POSITION)), sub(shl(176, 1), 1)) }
            }

            uint64 exporterTotal = processorsFees - (feeShare << 1);
            uint64 exporterHalf  = exporterTotal / 2;
            uint64 protocolShare = exporterTotal - exporterHalf;

            // Same type filter as the exporters: a proposer key sendfees cannot pay goes to the notary pool.
            setExporterFees(proposer, feeShare);
            setExporterFees(exporters[1], exporterHalf);

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
                setExporterFees(exporters[0], protocolShare);
            } else if (protocolShare <= verusToERC20mapping[VETH].tokenIndex) {
                // Neither a refused send nor a share the vETH ledger does not cover reverts the release. A refused
                // share is still held by the bridge, so it goes to the notary pool. An uncovered share is not
                // credited to anyone.
                // + the value-transfer (9,000) and cold-account (2,600) charges of the call, with margin.
                require(gasleft() > PROTOCOL_SHARE_GAS + 15000 + (PROTOCOL_SHARE_GAS + 15000) / 32);
                (bool success, ) = payable(VerusConstants.VERUS_USAGE_CONTRACT).call{value: protocolShare * VerusConstants.SATS_TO_WEI_STD, gas: PROTOCOL_SHARE_GAS}("");
                if (success) {
                    verusToERC20mapping[VETH].tokenIndex -= protocolShare;
                } else {
                    claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL] += protocolShare;
                }
            }
        }
    }

    function setClaimedFees(bytes32 _address, uint256 fees) private {
        claimableFees[_address] += fees;
    }

    /// @dev Credits an exporter only when it is a 20-byte R-address or i-address, the only keys sendfees pays out.
    ///      Any other shape could land on a system key in claimableFees (halt flags, reserves), so it goes to the notary pool.
    function setExporterFees(uint176 exporter, uint256 fees) private {
        uint16 typeAndLength = uint16(exporter >> VerusConstants.UINT160_BITS_SIZE);
        if ((typeAndLength == ((uint16(VerusConstants.DEST_PKH) << 8) | 20) || typeAndLength == ((uint16(VerusConstants.DEST_ID) << 8) | 20))
                && uint160(exporter) != 0) {
            setClaimedFees(bytes32(uint256(exporter)), fees);
        } else {
            claimableFees[VerusConstants.VDXF_SYSTEM_NOTARIZATION_NOTARYFEEPOOL] += fees;
        }
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
