// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "../Storage/StorageMaster.sol";

contract Delegator is VerusStorage {
    
    constructor(AddressMapper _mapper) {
        mapper  = _mapper;
        poolSize = 500000000000;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    receive() external payable {
        
    }

    function export(bytes memory data) payable external {

        address logic = mapper.getLogicContract(uint(VerusConstants.ContractType.VerusBridge));
        (bool success,) = logic.delegatecall(abi.encodeWithSignature("export(bytes)", data));
        require(success);
    }

    function submitImports(bytes calldata data) external { 


        bool success;
        bytes memory returnedData;

        address verusBridgeAddress = mapper.getLogicContract(uint(VerusConstants.ContractType.VerusBridge));
        (success, returnedData) = verusBridgeAddress.delegatecall(abi.encodeWithSignature("_createImports(bytes)", data));
        require(success);

        uint64 fees = abi.decode(returnedData, (uint64));

        if (fees > 0 ) {
            (success,) = verusBridgeAddress.delegatecall(abi.encodeWithSignature("setClaimableFees(uint64)", fees));
            require(success);
        }
    }

    function getReadyExportsByRange(uint256 _startBlock, uint256 _endBlock) external returns(VerusObjects.CReserveTransferSetCalled[] memory returnedExports){

        address logic = mapper.getLogicContract(uint(VerusConstants.ContractType.VerusBridge));

        (bool success, bytes memory returnedData) = logic.delegatecall(abi.encodeWithSignature("getReadyExportsByRange(uint256,uint256)", _startBlock, _endBlock));
        require(success);

        return abi.decode(returnedData, (VerusObjects.CReserveTransferSetCalled[]));
    }
    
    function setLatestData(bytes calldata serializedNotarization, bytes32 txid, uint32 n, bytes calldata data) external {

        address logic = mapper.getLogicContract(uint(VerusConstants.ContractType.VerusNotarizer));

        (bool success, ) = logic.delegatecall(abi.encodeWithSignature("setLatestData(bytes,bytes32,uint32,bytes)", serializedNotarization, txid, n, data));
        require(success);

    }

    function launchContractTokens() public {

    }
}