// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;
pragma abicoder v2;

import "./Blake2b.sol";

library VerusBlake2b {
    using Blake2b for Blake2b.Instance;

    function createHash(bytes memory input) public view returns (bytes32) {
      Blake2b.Instance memory instance = Blake2b.init(hex"", 32, true);
      return bytesToBytes32(instance.finalize(input));
    }

    function createDefaultHash(bytes memory input) public view returns (bytes32) {
      Blake2b.Instance memory instance = Blake2b.init(hex"", 32, false);
      return bytesToBytes32(instance.finalize(input));
    }

    function bytesToBytes32(bytes memory b) public pure returns (bytes32) {
        bytes32 out;

        assembly {
            out := mload(add(b, 32))
        }
        return out;
    }    

}