// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 < 0.9.0;
library VerusAddressCalculator{

    
    function stringToAddress(string memory value) public pure returns(address){
        bytes32 interimString = stringToBytes32(value);
        return address(bytes20(interimString));   
    }

    function addressToString(address value) public pure returns(string memory){
        //convert to bytes20
        return bytes20ToString(bytes20(value));
    }

    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        assembly {
            result := mload(add(source, 32))
        }
    }

    function uint160ToAddress(address value) public pure returns(address){
        return address(value);
    }

    function addressToUint160(address value) public pure returns(uint160){
        return uint160(value);
    }

    function bytes20ToString(bytes32 x) public pure returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 20; j++) {
            bytes1 char = bytes1(bytes32(uint256(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }

}