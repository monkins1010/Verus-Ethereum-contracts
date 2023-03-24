// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../Storage/StorageMaster.sol";

contract Delegator is VerusStorage {
    
    constructor() {
        poolSize = 500000000000;
    }
    
    receive() external payable {
        
    }

    function submitImports(bytes calldata data) external { 

        bool success;
        bytes memory returnedData;

        address verusBridgeAddress = contracts[uint(VerusConstants.ContractType.CreateExport)];
        (success, returnedData) = verusBridgeAddress.delegatecall(abi.encodeWithSignature("_createImports(bytes)", data));
        require(success);

        uint64 fees = abi.decode(returnedData, (uint64));

        if (fees > 0 ) {
            (success,) = verusBridgeAddress.delegatecall(abi.encodeWithSignature("setClaimableFees(uint64)", fees));
            require(success);
        }
    }

    function getReadyExportsByRange(uint256 _startBlock, uint256 _endBlock) external returns(VerusObjects.CReserveTransferSetCalled[] memory returnedExports){

        address logic = contracts[uint(VerusConstants.ContractType.CreateExport)];

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

        address logic = contracts[uint(VerusConstants.ContractType.VerusNotaryTools)];

        (bool success,) = logic.delegatecall(abi.encodeWithSignature("launchContractTokens(data)", data));
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
    }

    function getProofByHeight(uint height) public payable returns (bytes memory) {

       // return verusNotarizer.getProof(height);
    }

    function getProofCost(bool latest) public view returns (uint256) {

      //  return verusNotarizer.getProofCosts(latest);
    }

    function setInitialContracts(address[] memory _newContractAddress) external {

        address upgradeManagerAddress = contracts[uint(VerusConstants.ContractType.UpgradeManager)];

        (bool success,) = upgradeManagerAddress.delegatecall(abi.encodeWithSignature("setInitialContracts(address[])", _newContractAddress));
        require(success);

    }
}