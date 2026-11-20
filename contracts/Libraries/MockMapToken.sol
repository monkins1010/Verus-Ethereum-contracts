// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;
pragma abicoder v2;

import "../Storage/StorageMaster.sol";

/// @dev TEST ONLY. Installed with Delegator.replacecontract, its initialize() maps a Verus currency to an existing
///      ERC-20, as a currency definition mapped to an Ethereum-owned token does on mainnet. Anyone can define such a
///      currency on Verus, so the mapped token may be hostile. Never deploy to production.
contract MockMapToken is VerusStorage {

    address immutable IADDRESS;
    address immutable ERC20_ADDRESS;
    uint8 immutable FLAGS;

    constructor(address iaddress, address erc20Address, uint8 flags) {
        IADDRESS = iaddress;
        ERC20_ADDRESS = erc20Address;
        FLAGS = flags;
    }

    function initialize() external {
        verusToERC20mapping[IADDRESS] = VerusObjects.mappedToken(ERC20_ADDRESS, FLAGS, 0, "Hostile", 0);
        tokenList.push(IADDRESS);
    }
}
