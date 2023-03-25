// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.4.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';

contract Token is ERC20 {

    address private owner;

    constructor(string memory _name, string memory _symbol) ERC20(_name,_symbol) {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == owner,"Only the contract owner can Mint Tokens");
        _mint(to, amount);

    }
    
    function burn(uint256 amount) public virtual {
        require(msg.sender == owner,"Only the contract owner can Burn Tokens");
        _burn(_msgSender(), amount);
    }
    function changeowner(address newOwner) public virtual {
        require(msg.sender == owner,"Only the contract owner can update the owner");
        owner = newOwner;
    }
}

contract VerusNft is ERC721URIStorage {
  
    address private owner;

    constructor() ERC721('VerusNFT', 'vNFT') {
        owner = msg.sender;
    }
    
    function mint(address tokenId, string memory inTokenURI, address recipient) public {
        require(msg.sender == owner,"Only the contract owner can Mint NFTS");
        _mint(recipient, uint256(uint160(tokenId)));
        _setTokenURI(uint256(uint160(tokenId)), inTokenURI);

    }

    function burn(uint256 tokenId) public {
        require(msg.sender == owner,"Only the contract owner can Burn NFTS");
        _burn(tokenId);
    }
    
    function changeowner(address newOwner) public virtual {
        require(msg.sender == owner,"Only the contract owner can update the owner");
        owner = newOwner;
    }
}
