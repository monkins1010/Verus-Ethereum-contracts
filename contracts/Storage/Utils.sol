// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

library Utils {
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
    
    function reverse(uint64 input) public pure returns (uint64 v) 
    {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = (v >> 32) | (v << 32);
    }
}