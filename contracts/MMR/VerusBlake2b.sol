// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9;
pragma abicoder v2;

import "./Blake2b.sol";

library VerusBlake2b {
    using Blake2b for Blake2b.Instance;

    function createHash(bytes memory input) public view returns (bytes32) {
      Blake2b.Instance memory instance = Blake2b.init(hex"", 32);
      return instance.finalize(input);
    }

}