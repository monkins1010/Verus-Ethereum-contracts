// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.20;

import "../../node_modules/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {

    address private owner;

    constructor(string memory _name, string memory _symbol) ERC20(_name,_symbol) public {
        owner = msg.sender;
    }

    function mint(address to,uint256 amount) public {
        require(msg.sender == owner,"Only the contract owner can Mint Tokens");
        _mint(to, amount);

    }
    
    function burn(uint256 amount) public virtual {
        require(msg.sender == owner,"Only the contract owner can Burn Tokens");
        _burn(_msgSender(), amount);
    }
}
