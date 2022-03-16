// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "./Blake2b.sol";

contract VerusBlake2b {
    using Blake2b for Blake2b.Instance;

    function createHash(bytes memory input) public view returns (bytes32) {
      Blake2b.Instance memory instance = Blake2b.init(hex"", 32);
      return bytesToBytes32(instance.finalize(input));
    }

    function bytesToBytes32(bytes memory b)
        public
        pure
        returns (bytes32)
    {
        bytes32 out;

        for (uint256 i = 0; i < 32; i++) {
            out |= bytes32(b[(i)] & 0xFF) >> (i * 8);
        }
        return out;
    }    

}