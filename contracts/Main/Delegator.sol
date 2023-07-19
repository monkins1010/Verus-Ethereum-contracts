// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
pragma abicoder v2;

import "../Storage/StorageMaster.sol";
import "../VerusBridge/Token.sol";

contract Delegator is VerusStorage {

    address startOwner;
    
    constructor(address[] memory _notaries, address[] memory _notariesEthAddress, address[] memory _notariesColdStoreEthAddress, address[] memory _newContractAddress) {
        remainingLaunchFeeReserves = VerusConstants.verusBridgeLaunchFeeShare;

        for(uint i =0; i < _notaries.length; i++) {
            notaryAddressMapping[_notaries[i]] = VerusObjects.notarizer(_notariesEthAddress[i], _notariesColdStoreEthAddress[i], VerusConstants.NOTARY_VALID);
            notaries.push(_notaries[i]);
            notariesEthAddress[_notariesEthAddress[i]] = true;
        }
        VerusNft t = new VerusNft(); 

        verusToERC20mapping[VerusConstants.VerusNFTID] = 
            VerusObjects.mappedToken(address(t), uint8(VerusConstants.MAPPING_VERUS_OWNED + VerusConstants.TOKEN_ETH_NFT_DEFINITION),
                0, "VerusNFT", uint256(0));  

        tokenList.push(VerusConstants.VerusNFTID);

        startOwner = msg.sender;
        for (uint i = 0; i < uint(VerusConstants.NUMBER_OF_CONTRACTS); i++) {
            contracts.push(_newContractAddress[i]);
        }
    }
    
    receive() external payable {
        
    }

    function sendTransfer(VerusObjects.CReserveTransfer calldata _transfer) external payable { 

        bool success;
        bytes memory data = abi.encode(_transfer); 

        address verusBridgeAddress = contracts[uint(VerusConstants.ContractType.CreateExport)];
        (success, ) = verusBridgeAddress.delegatecall(abi.encodeWithSignature("sendTransfer(bytes)", data));
        require(success);
    }

    function submitImports(VerusObjects.CReserveTransferImport calldata data) external { 

        bool success;
        bytes memory returnedData;

        bytes memory packedData = abi.encode(data);

        address SubmitImportsAddress = contracts[uint(VerusConstants.ContractType.SubmitImports)];
        (success, returnedData) = SubmitImportsAddress.delegatecall(abi.encodeWithSignature("_createImports(bytes)", packedData));
        require(success);

        (uint64 fees, uint176 exporter) = abi.decode(returnedData, (uint64, uint176));

        if (fees > 0 ) {
            (success,) = SubmitImportsAddress.delegatecall(abi.encodeWithSignature("setClaimableFees(uint64,uint176)", fees, exporter));
            require(success);
        }
    }

    function getReadyExportsByRange(uint256 _startBlock, uint256 _endBlock) external returns(VerusObjects.CReserveTransferSetCalled[] memory returnedExports){

        address logic = contracts[uint(VerusConstants.ContractType.SubmitImports)];

        (bool success, bytes memory returnedData) = logic.delegatecall(abi.encodeWithSignature("getReadyExportsByRange(uint256,uint256)", _startBlock, _endBlock));
        require(success);

        return abi.decode(returnedData, (VerusObjects.CReserveTransferSetCalled[]));
    }
    
    function setLatestData(bytes calldata serializedNotarization, bytes32 txid, uint32 n, bytes calldata data) external {

        address logic = contracts[uint(VerusConstants.ContractType.VerusNotarizer)];

        (bool success, ) = logic.delegatecall(abi.encodeWithSignature("setLatestData(bytes,bytes32,uint32,bytes)", serializedNotarization, txid, n, data));
        require(success);

    }

    function launchContractTokens(bytes calldata data) external  {

        require(verusToERC20mapping[VerusConstants.VEth].flags == 0);
        address logic = contracts[uint(VerusConstants.ContractType.TokenManager)];

        (bool success,) = logic.delegatecall(abi.encodeWithSignature("launchContractTokens(bytes)", data));
        require(success);

    }

    function getTokenList(uint256 start, uint256 end) external returns(VerusObjects.setupToken[] memory ) {
        
        address logic = contracts[uint(VerusConstants.ContractType.VerusProof)];

        (bool success, bytes memory returnedData) = logic.delegatecall(abi.encodeWithSignature("getTokenList(uint256,uint256)", start, end));
        require(success);

        return abi.decode(returnedData, (VerusObjects.setupToken[]));

    }

    function checkImport(bytes32 _imports) public view returns(bool){
        return processedTxids[_imports];
    }

    function claimfees() external {
        address submitImportAddress = contracts[uint(VerusConstants.ContractType.SubmitImports)];

        (bool success,) = submitImportAddress.delegatecall(abi.encodeWithSignature("claimfees()"));
        require(success);

    }

    function claimRefund(uint176 verusAddress) external {
        address submitImportAddress = contracts[uint(VerusConstants.ContractType.SubmitImports)];

        (bool success,) = submitImportAddress.delegatecall(abi.encodeWithSignature("claimRefund(uint176)", verusAddress));
        require(success);

    }

    function sendfees(bytes32 publicKeyX, bytes32 publicKeyY) external {
        address submitImportAddress = contracts[uint(VerusConstants.ContractType.SubmitImports)];

        (bool success,) = submitImportAddress.delegatecall(abi.encodeWithSignature("sendfees(bytes32,bytes32)", publicKeyX, publicKeyY));
        require(success);

    } 

    function getNewProof(bool latest) public payable returns (bytes memory) {
                
        address VerusNotaryToolsAddress = contracts[uint(VerusConstants.ContractType.VerusNotaryTools)];
        (bool success, bytes memory returnedData) = VerusNotaryToolsAddress.delegatecall(abi.encodeWithSignature("getNewProof(bool)", latest));

        require(success);
        return abi.decode(returnedData, (bytes));
    }

    function getProofByHeight(uint256 height) external returns (bytes memory) {

        address VerusNotaryToolsAddress = contracts[uint(VerusConstants.ContractType.VerusNotaryTools)];
        (bool success, bytes memory returnedData) = VerusNotaryToolsAddress.delegatecall(abi.encodeWithSignature("getProof(uint256)", height));

        require(success);
        return abi.decode(returnedData, (bytes));
    }

    function getProofCost(bool latest) external returns (uint256) {
                
        address VerusNotaryToolsAddress = contracts[uint(VerusConstants.ContractType.VerusNotaryTools)];
        (bool success, bytes memory returnedData) = VerusNotaryToolsAddress.delegatecall(abi.encodeWithSignature("getProofCosts(bool)", latest));

        require(success);
        return abi.decode(returnedData, (uint256));

    }

    function upgradeContracts(bytes calldata data) external payable returns (uint8) {

        address upgradeManagerAddress = contracts[uint(VerusConstants.ContractType.UpgradeManager)];

        (bool success, bytes memory returnedData) = upgradeManagerAddress.delegatecall(abi.encodeWithSignature("upgradeContracts(bytes)", data));
        require(success);
        
        return abi.decode(returnedData, (uint8));
    }

    function replacecontract(address newcontract, uint contractNo) external  {
        require(startOwner == msg.sender);
        if(contractNo == 100) {
            startOwner = address(0);
            return;
        } 
        contracts[contractNo] = newcontract;
    }

    function runContractsUpgrade() public returns (uint8) {
      
        address upgradeManagerAddress = contracts[uint(VerusConstants.ContractType.UpgradeManager)];

        (bool success, bytes memory returnedData) = upgradeManagerAddress.delegatecall(abi.encodeWithSignature("runContractsUpgrade()"));
        require(success);
        return abi.decode(returnedData, (uint8));
    }

    function revokeWithMainAddress(bytes calldata data) external returns (bool) { 

        address VerusNotaryToolsAddress = contracts[uint(VerusConstants.ContractType.VerusNotaryTools)];

        (bool success, bytes memory returnedData) = VerusNotaryToolsAddress.delegatecall(abi.encodeWithSignature("revokeWithMainAddress(bytes)", data));
        require(success);
        return abi.decode(returnedData, (bool));

    }

    function revokeWithMultiSig(bytes calldata data) external returns (bool) { 

        address VerusNotaryToolsAddress = contracts[uint(VerusConstants.ContractType.VerusNotaryTools)];

        (bool success, bytes memory returnedData) = VerusNotaryToolsAddress.delegatecall(abi.encodeWithSignature("revokeWithMultiSig(bytes)", data));
        require(success);
        return abi.decode(returnedData, (bool));

    }

    function recoverWithRecoveryAddress(bytes calldata data) external returns (uint8) {

        address VerusNotaryToolsAddress = contracts[uint(VerusConstants.ContractType.VerusNotaryTools)];

        (bool success, bytes memory returnedData) = VerusNotaryToolsAddress.delegatecall(abi.encodeWithSignature("recoverWithRecoveryAddress(bytes)", data));
        require(success);

        return abi.decode(returnedData, (uint8));
    }

    function recoverWithMultiSig(bytes calldata data) external returns (uint8) {

        address VerusNotaryToolsAddress = contracts[uint(VerusConstants.ContractType.VerusNotaryTools)];

        (bool success, bytes memory returnedData) = VerusNotaryToolsAddress.delegatecall(abi.encodeWithSignature("recoverWithMultiSig(bytes)", data));
        require(success);

        return abi.decode(returnedData, (uint8));
    }

    function getVoteState(uint item) public view returns (VerusObjects.voteState memory) {

        return pendingVoteState[item];

    }
}