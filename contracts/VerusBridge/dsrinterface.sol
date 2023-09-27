// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.8.9;
pragma abicoder v2;

interface VatLike {
    function hope(address) external;
}

interface PotLike {
    function vat() external view returns (address);
    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;
}

interface JoinLike {
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}