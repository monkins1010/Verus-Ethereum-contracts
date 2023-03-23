// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

contract AddressMapper {
    
    address delegator;
    address[] internal contracts;
    
    address public owner;
    
    constructor(address upgradeManager) {
        owner = upgradeManager;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    function transferOwnership(address _newOwner) external onlyOwner {
        
        require(_newOwner != address(0), "invalid address");
        
        owner = _newOwner;
    }
    
    function setDelegator(address _delegator) external onlyOwner {
        delegator = _delegator;
    }
 
    function getDelegator() external view returns (address) {
        return delegator;
    }
    
    function addLogicContract(address _logicContract) external onlyOwner {
        contracts.push(_logicContract);
    }
    
    function replaceLogicContract(uint number, address _logicContract) external onlyOwner {
        contracts[number] = _logicContract;
    }
    
    function getLogicContract(uint number) external view returns (address) {
        return contracts[number];
    }
}