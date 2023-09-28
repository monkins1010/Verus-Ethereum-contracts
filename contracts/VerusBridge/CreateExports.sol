// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "./Token.sol";
import "./VerusCrossChainExport.sol";
import "./CreateExports.sol";
import "../Storage/StorageMaster.sol";
import "./ExportManager.sol";
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "./SubmitImports.sol";

contract CreateExports is VerusStorage {

    address immutable VETH;
    address immutable BRIDGE;
    address immutable VERUS;
    address immutable DAI;
    address immutable DAIERC20ADDRESS;

    using SafeERC20 for Token;

    constructor(address vETH, address Bridge, address Verus, address Dai, address daiERC20Address){

        VETH = vETH;
        BRIDGE = Bridge;
        VERUS = Verus;
        DAI = Dai;
        DAIERC20ADDRESS = daiERC20Address;
    }

    function subtractPoolSize(uint64 _amount) private returns (bool) {

        if((_amount + VerusConstants.MIN_VRSC_FEE) > remainingLaunchFeeReserves) return false;
        remainingLaunchFeeReserves -= _amount;
        return true;
    }

    function sendTransfer(bytes calldata datain) payable external {

        VerusObjects.CReserveTransfer memory transfer = abi.decode(datain, (VerusObjects.CReserveTransfer));        
        sendTransferMain(transfer);
    }

    function sendTransferDirect(bytes calldata datain) payable external {

        address serializerAddress = contracts[uint(VerusConstants.ContractType.VerusSerializer)];

        (bool success, bytes memory returnData) = serializerAddress.call(abi.encodeWithSignature("deserializeTransfer(bytes)",datain));

        require(success, "deserializetransfer failed");  

        VerusObjects.CReserveTransfer memory transfer = abi.decode(returnData, (VerusObjects.CReserveTransfer));
        sendTransferMain(transfer);
    }
 
    function sendTransferMain(VerusObjects.CReserveTransfer memory transfer) private {

        uint256 fees;
        VerusObjects.mappedToken memory iaddressMapping;
        uint32 ethNftFlag;
        address verusExportManagerAddress = contracts[uint(VerusConstants.ContractType.ExportManager)];

        (bool success, bytes memory returnData) = verusExportManagerAddress.delegatecall(abi.encodeWithSelector(ExportManager.checkExport.selector, transfer));
        require(success, "checkExport call failed");

        fees = abi.decode(returnData, (uint256)); 

        require(fees != 0, "CheckExport Failed Checks"); 

        if(!bridgeConverterActive) {
            require (subtractPoolSize(uint64(transfer.fees)));
        }

        if (transfer.currencyvalue.currency != VETH) {
            iaddressMapping = verusToERC20mapping[transfer.currencyvalue.currency];
            ethNftFlag = iaddressMapping.flags & (VerusConstants.MAPPING_ERC721_NFT_DEFINITION | VerusConstants.MAPPING_ERC1155_NFT_DEFINITION | VerusConstants.MAPPING_ERC1155_ERC_DEFINITION);
        }

        if (ethNftFlag != 0) { //handle a NFT Import

            if (ethNftFlag == VerusConstants.MAPPING_ERC1155_NFT_DEFINITION || ethNftFlag == VerusConstants.MAPPING_ERC1155_ERC_DEFINITION) {
                IERC1155 nft = IERC1155(iaddressMapping.erc20ContractAddress);

                // TokenIndex is used for ERC1155's only for the amount of tokens held by the bridge
                require((transfer.currencyvalue.amount + iaddressMapping.tokenIndex) < VerusConstants.MAX_VERUS_TRANSFER);
                verusToERC20mapping[transfer.currencyvalue.currency].tokenIndex += transfer.currencyvalue.amount;

                require (nft.isApprovedForAll(msg.sender, address(this)), "NFT not approved");
                nft.safeTransferFrom(msg.sender, address(this), iaddressMapping.tokenID, transfer.currencyvalue.amount, ""); 
      

            } else if (ethNftFlag == VerusConstants.MAPPING_ERC721_NFT_DEFINITION){
                VerusNft nft = VerusNft(iaddressMapping.erc20ContractAddress);
                require (nft.getApproved(iaddressMapping.tokenID) == address(this), "NFT not approved");
                nft.safeTransferFrom(msg.sender, address(this), iaddressMapping.tokenID, "");

                if (iaddressMapping.erc20ContractAddress == verusToERC20mapping[tokenList[VerusConstants.NFT_POSITION]].erc20ContractAddress) {
                    nft.burn(iaddressMapping.tokenID);
                }
            } else {
                revert();
            }
         } else if (transfer.currencyvalue.currency != VETH) {

            Token token = Token(iaddressMapping.erc20ContractAddress); 
            //Check user has allowed the verusBridgeStorage contract to spend on their behalf
            uint256 allowedTokens = token.allowance(msg.sender, address(this));
            uint256 tokenAmount = convertFromVerusNumber(transfer.currencyvalue.amount, token.decimals()); //convert to wei from verus satoshis
            require( allowedTokens >= tokenAmount);

            if (iaddressMapping.flags & VerusConstants.MAPPING_ETHEREUM_OWNED == VerusConstants.MAPPING_ETHEREUM_OWNED) {
                // TokenID is used for ERC20's only for the amount of tokens held by the bridge

                require((transfer.currencyvalue.amount + iaddressMapping.tokenID) < VerusConstants.MAX_VERUS_TRANSFER);
                    verusToERC20mapping[transfer.currencyvalue.currency].tokenID += transfer.currencyvalue.amount;
                
            }

            exportERC20Tokens(tokenAmount, token, iaddressMapping.flags & VerusConstants.MAPPING_VERUS_OWNED == VerusConstants.MAPPING_VERUS_OWNED);
        } 

        _createExports(transfer, false);
    }

    function exportERC20Tokens(uint256 _tokenAmount, Token token, bool burn) public {
        
        token.safeTransferFrom(msg.sender, address(this), _tokenAmount);

        // If the token is DAI, run join to have the DAI transferred to the DSR contract.
        if (address(token) == DAIERC20ADDRESS) {
            address crossChainExportAddress = contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)];
            (bool success,) = crossChainExportAddress.delegatecall(abi.encodeWithSignature("join(uint256)", _tokenAmount));
            require(success);
        }

        if (burn) 
        {
            token.burn(_tokenAmount);
        }
    }

    function externalCreateExportCallPayable(bytes memory data) external payable {

        (VerusObjects.CReserveTransfer memory reserveTransfer, bool forceNewCCE) = abi.decode(data, (VerusObjects.CReserveTransfer, bool));
        _createExports(reserveTransfer, forceNewCCE);
    }

    function externalCreateExportCall(bytes memory data) external {

        (VerusObjects.CReserveTransfer memory reserveTransfer, bool forceNewCCE) = abi.decode(data, (VerusObjects.CReserveTransfer, bool));
        _createExports(reserveTransfer, forceNewCCE);
    }

    function _createExports(VerusObjects.CReserveTransfer memory reserveTransfer, bool forceNewCCE) private {

        // If transactions over 50 and inbetween notarization boundaries, increment CCE start and endheight
        // If notarization has happened increment CCE to next boundary when the tx comes in
        // If changing from pool closed to pool open create a boundary (As all sends will then go through the bridge)
        uint64 blockNumber = uint64(block.number);
        uint64 blockDelta = blockNumber - cceLastStartHeight;
        uint64 lastTransfersLength = uint64(_readyExports[cceLastStartHeight].transfers.length);
        bytes32 prevHash = _readyExports[cceLastStartHeight].exportHash;
        // if there are no transfers then there is no need to make a new CCE as this is the first one, and the endheight can become the block number if it is less than the current block no.
        // if the last notary received height is less than the endheight then keep building up the CCE (as long as 10 ETH blocks havent passed, and a new CCE isnt being forced and there is less than 50)

        if ((cceLastEndHeight == 0 || blockDelta < 10) && !forceNewCCE  && lastTransfersLength < 50) {

            // set the end height of the CCE to the current block.number only if the current block we are on is greater than its value
            if (cceLastEndHeight < blockNumber) {
                cceLastEndHeight = blockNumber;
            }
        // if a new CCE is triggered for any reason, its startblock is always the previous endblock +1, 
        // its start height may of spilled in to virtual future block numbers so if the current cce start height is less than the block we are on we can update the end 
        // height to a new greater value.  Otherwise if the startheight is still in the future then the endheight is also in the future at the same block.
        } else {
            cceLastStartHeight = cceLastEndHeight + 1;

            if (cceLastStartHeight < blockNumber) {
                cceLastEndHeight = blockNumber;
            } else {
                cceLastEndHeight = cceLastStartHeight;
            }
        }

        if (exportHeights[cceLastEndHeight] != cceLastStartHeight) {
            exportHeights[cceLastEndHeight] = cceLastStartHeight;
        }

        setReadyExportTransfers(cceLastStartHeight, cceLastEndHeight, reserveTransfer, 50);
        VerusObjects.CReserveTransferSet memory pendingTransfers = _readyExports[cceLastStartHeight];
        address crossChainExportAddress = contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)];

        (bool success, bytes memory returnData) = crossChainExportAddress.call(abi.encodeWithSignature("generateCCE(bytes)", abi.encode(pendingTransfers.transfers, bridgeConverterActive, cceLastStartHeight, cceLastEndHeight, contracts[uint(VerusConstants.ContractType.VerusSerializer)])));
        require(success, "generateCCEfailed");

        bytes memory serializedCCE = abi.decode(returnData, (bytes)); 

        if(pendingTransfers.transfers.length > 1)
        {
            prevHash = pendingTransfers.prevExportHash;
        }
        setReadyExportTxid(keccak256(abi.encodePacked(serializedCCE, prevHash)), prevHash, cceLastStartHeight);

    }

    function setReadyExportTxid(bytes32 txidhash, bytes32 prevTxidHash, uint _block) private {
        
        _readyExports[_block].exportHash = txidhash;

        if (_readyExports[_block].transfers.length == 1)
        {
            _readyExports[_block].prevExportHash = prevTxidHash;

        }
    }

    function setReadyExportTransfers(uint64 _startHeight, uint64 _endHeight, VerusObjects.CReserveTransfer memory reserveTransfer, uint blockTxLimit) private {
        
        _readyExports[_startHeight].endHeight = _endHeight;
        _readyExports[_startHeight].transfers.push(reserveTransfer);
        require(_readyExports[_startHeight].transfers.length <= blockTxLimit);
      
    }

    function burnFees(bytes calldata) external {

        require(bridgeConverterActive, "Bridge Converter not active");
        
        uint256 interestAccrued;
        uint64 truncatedVerus;
        bool success;
        bytes memory retData;
        
        // NOTE: Accrued intrest is truncated to 18 decimals.  Needs to be truncated to be sent to verus.
        address crossChainExportAddress = contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)];
        (success, retData) = crossChainExportAddress.delegatecall(abi.encodeWithSelector(VerusCrossChainExport.daiBalance.selector));
        require(success);

        mapping (bytes32 => uint256) storage daiTotals = claimableFees;

        interestAccrued = abi.decode(retData, (uint256)) - daiTotals[VerusConstants.VDXF_SYSTEM_DAI_HOLDINGS];

        uint256 bridgeReserveValues = daiTotals[bytes32(uint256(uint160(VerusConstants.VDXF_ETH_DAI_VRSC_LAST_RESERVES)))];
        uint64 daiToETHRatio = uint64(bridgeReserveValues) / uint64(bridgeReserveValues >> 64);
        // Caclulate how much the submitter of this transaction should be reimbursed for the gas used to burn the DAI.
        uint64 DAIReimburseAmount = uint64(((tx.gasprice * VerusConstants.DAI_BURNBACK_TRANSACTION_GAS_AMOUNT)/ VerusConstants.SATS_TO_WEI_STD) 
                                             * daiToETHRatio);

        require (DAIReimburseAmount < VerusConstants.DAI_BURNBACK_MAX_FEE_THRESHOLD, "DAI Burnback Fee too high");

        //truncate DAI to 8 DECIMALS of precision from 18
        truncatedVerus = uint64(interestAccrued / VerusConstants.SATS_TO_WEI_STD);
        interestAccrued = (truncatedVerus * VerusConstants.SATS_TO_WEI_STD) - DAIReimburseAmount;
        
        if (interestAccrued > VerusConstants.DAI_BURNBACK_THRESHOLD) {
            // Increase the supply of DAI by the amount of intrest accrued - minus the payback fee.
            daiTotals[VerusConstants.VDXF_SYSTEM_DAI_HOLDINGS] += interestAccrued;

            (success, retData) = contracts[uint(VerusConstants.ContractType.SubmitImports)].delegatecall(abi.encodeWithSelector(SubmitImports.sendToVRSC.selector, truncatedVerus, address(0), VerusConstants.DEST_PKH, DAI));
            require(success);
                   // When the bridge launches to make sure a fresh block with no pending vrsc transfers is used as not to mix destination currencies.
            (VerusObjects.CReserveTransfer memory LPtransfer,) = abi.decode(retData, (VerusObjects.CReserveTransfer, bool)); 

            _createExports(LPtransfer, false);

            //transfer DAI to the msg.senders address.
            (success,) = crossChainExportAddress.delegatecall(abi.encodeWithSelector(VerusCrossChainExport.exit.selector, msg.sender, DAIReimburseAmount * VerusConstants.SATS_TO_WEI_STD));
            require(success);
        }

    }
        
    function convertFromVerusNumber(uint256 a,uint8 decimals) public pure returns (uint256) {
        uint8 power = 10; //default value for 18
        uint256 c = a;

        if(decimals > 8 ) {
            power = decimals - 8;// number of decimals in verus
            c = a * (10 ** power);
        }else if(decimals < 8){
            power = 8 - decimals;// number of decimals in verus
            c = a / (10 ** power);
        }
      
        return c;
    }
}
