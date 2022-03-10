// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusObjectsNotarization.sol";

import "./TokenManager.sol";    
import "./VerusSerializer.sol";
import "../MMR/VerusProof.sol";
import "./VerusCrossChainExport.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusBridge.sol";
import "./VerusInfo.sol";
import "./ExportManager.sol";

contract VerusBridgeMaster {

    //declare the contracts and have it return the contract addresses

    TokenManager tokenManager;
    VerusSerializer verusSerializer;
    VerusProof verusProof;
    VerusCrossChainExport verusCCE;
    VerusNotarizer verusNotarizer;
    VerusBridge verusBridge;
    VerusInfo verusInfo;
    ExportManager exportManager;

    //temporary placeholder for testing purposes
    address contractOwner;
    
    //all major functions get declared here and passed through to the underlying contract
    uint256 feesHeld = 0;
    uint256 ethHeld = 0;
    uint256 poolSize = 0;

    mapping (address => uint256) public claimableFees;
    
    //contract allows the contracts to be set and reset
    constructor(
        uint256 _poolSize){
            contractOwner = msg.sender; 
            poolSize = _poolSize;        
    }
    
    /** get and set functions, sets to be performed by the notariser **/
    function setContractAddress(VerusConstants.ContractType contractTypeAddress, address _newContractAddress) public {
        assert(msg.sender == contractOwner);
        if(contractTypeAddress == VerusConstants.ContractType.TokenManager){
            tokenManager = TokenManager(_newContractAddress);
        }
        else if(contractTypeAddress == VerusConstants.ContractType.VerusSerializer){
            verusSerializer = VerusSerializer(_newContractAddress);
        } 
        else if(contractTypeAddress == VerusConstants.ContractType.VerusProof){
            verusProof =  VerusProof(_newContractAddress);
        } 
        else if(contractTypeAddress == VerusConstants.ContractType.VerusCrossChainExport){
            verusCCE = VerusCrossChainExport(_newContractAddress);        
        }        
        else if(contractTypeAddress == VerusConstants.ContractType.VerusNotarizer){
            verusNotarizer = VerusNotarizer(_newContractAddress);       
        }        
        else if(contractTypeAddress == VerusConstants.ContractType.VerusBridge){
            verusBridge = VerusBridge(_newContractAddress);       
        }
        else if(contractTypeAddress == VerusConstants.ContractType.VerusInfo){
            verusInfo = VerusInfo(_newContractAddress);       
        }
        else if(contractTypeAddress == VerusConstants.ContractType.ExportManager){
            exportManager = ExportManager(_newContractAddress);       
        }
    }
    
    /** returns the address of each contract to be used by the sub contracts **/
    function getContractAddress(VerusConstants.ContractType contractTypeAddress) public view returns(address contractAddress){
        if(contractTypeAddress == VerusConstants.ContractType.TokenManager){
            contractAddress = address(tokenManager);
        }
        if(contractTypeAddress == VerusConstants.ContractType.VerusSerializer){
            contractAddress = address(verusSerializer);
        } 
        if(contractTypeAddress == VerusConstants.ContractType.VerusProof){
            contractAddress = address(verusProof);
        } 
        if(contractTypeAddress == VerusConstants.ContractType.VerusCrossChainExport){
            contractAddress = address(verusCCE);        
        }        
        if(contractTypeAddress == VerusConstants.ContractType.VerusNotarizer){
            contractAddress = address(verusNotarizer);       
        }        
        if(contractTypeAddress == VerusConstants.ContractType.VerusBridge){
            contractAddress = address(verusBridge);       
        }
        if(contractTypeAddress == VerusConstants.ContractType.VerusInfo){
            contractAddress = address(verusInfo);       
        }
    }

    function setFeesHeld(uint256 _feesAmount) public {
        require( msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        feesHeld = _feesAmount;
    }
    function getFeesHeld() public view returns(uint256){
        return feesHeld;
    }
    function addToFeesHeld(uint256 _feesAmount) public {
        require( msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        feesHeld += _feesAmount;
    }

    function addToEthHeld(uint256 _ethAmount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        ethHeld += _ethAmount;
    }
    function subtractFromEthHeld(uint256 _ethAmount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        ethHeld -= _ethAmount;
    }

    function setEthHeld(uint256 _ethAmount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        ethHeld = _ethAmount;
    }

    function getEthHeld() public view returns(uint256){
        return ethHeld;
    }

    function setPoolSize(uint256 _amount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        ethHeld = _amount;
    }

    function getPoolSize() public view returns(uint256){
        return poolSize;
    }

    function setClaimableFees(address _feeRecipient,uint256 _ethAmount) public {
        require(msg.sender == address(verusBridge),"This function can only be called by Verus Bridge");
        claimableFees[_feeRecipient] = claimableFees[_feeRecipient] + _ethAmount;
    }

    /** VerusBridge pass through functions **/
    function export(VerusObjects.CReserveTransfer memory _transfer) public payable {
        uint256 ethAmount = msg.value;
        verusBridge.export(_transfer,ethAmount);
    }

    function checkImports(bytes32[] memory _imports) public view returns(bytes32[] memory){
        return verusBridge.checkImports(_imports);
    }

    function submitImports(VerusObjects.CReserveTransferImport[] memory _imports) public {
        verusBridge.submitImports(_imports);
    }

    function getReadyExportsByRange(uint _startBlock, uint _endBlock) public view 
        returns(VerusObjects.CReserveTransferSet[] memory){
        return verusBridge.getReadyExportsByRange(_startBlock,_endBlock);
    }

    function readyExportHashes(uint _position) public view returns (bytes32) {
        return verusBridge.readyExportHashes(_position);
    }

    /** VerusNotarizer pass through functions **/

    function poolAvailable(address _address) public view returns(uint32){
        return verusNotarizer.poolAvailable(_address);
    }

    function getLastProofRoot() public view returns(VerusObjectsNotarization.CProofRoot memory){
        return verusNotarizer.getLastProofRoot();
    }

    function lastBlockHeight() public view returns(uint32){
        return verusNotarizer.lastBlockHeight();
    }

    function setLatestData(VerusObjectsNotarization.CPBaaSNotarization memory _pbaasNotarization,
        uint8[] memory _vs,
        bytes32[] memory _rs,
        bytes32[] memory _ss,
        uint32[] memory blockheights,
        address[] memory notaryAddress
        ) public returns(bool){
            return verusNotarizer.setLatestData(_pbaasNotarization,_vs,_rs,_ss,blockheights,notaryAddress);
    }

    /** VerusInfo pass through functions **/

     function getinfo() public view returns(VerusObjects.infoDetails memory){
         return verusInfo.getinfo();
     }

     function sendEth(uint256 _ethAmount, address payable _ethAddress) public {
         //only callable by verusbridge contract
        require(msg.sender == address(verusBridge),"Sorry you can't call this function");
        _ethAddress.transfer(_ethAmount);
     }

    function isPoolUnavailable(uint256 _feesAmount,address _feeCurrencyID) public view returns(bool){
        if(0 < verusNotarizer.poolAvailable(VerusConstants.VerusBridgeAddress) &&
            verusNotarizer.poolAvailable(VerusConstants.VerusBridgeAddress) < uint32(block.number)) {
            //the bridge has been activated
            return false;
        } else {
            assert(_feeCurrencyID == VerusConstants.VerusCurrencyId);
            assert(getPoolSize() >= _feesAmount);
            return true;
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

    function convertToVerusNumber(uint256 a,uint8 decimals) public pure returns (uint256) {
         uint8 power = 10; //default value for 18
         uint256 c = a;
        if (decimals > 8 ) {
            power = decimals - 8;// number of decimals in verus
            c = a / (10 ** power);
        } else if (decimals < 8){
            power = 8 - decimals;// number of decimals in verus
            c = a * (10 ** power);
        }

        return c;
    }

    function bytesToAddress(bytes memory bys) public pure returns (address addr) {
        assembly {
        addr := mload(add(bys,20))
        } 
    }


}