pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjectsCommon.sol";
import "../VerusBridge/VerusSerializer.sol";

contract Deserializer {
    VerusSerializer verusSerializer;
    uint32 constant CCC_PREFIX_TO_PARENT = 4 + 4 + 20;
    uint32 constant CCC_LAUNCH_ID_LEN = 20;

    constructor(address verusSerializerAddress) {
        verusSerializer = VerusSerializer(verusSerializerAddress);
    }

    function init(bytes memory input)
        internal
        view
        returns (
            VerusObjectsCommon.CcurrencyDefinition memory ccurrencyDefinition
        )
    {
        uint32 nextOffset;
        uint8 nameStringLength;
        address parent;
        address launchSystemID;

        nextOffset = CCC_PREFIX_TO_PARENT;

        assembly {
            parent := mload(add(input, nextOffset)) // this should be parent ID
            nextOffset := add(nextOffset, 1) // and after that...
            nameStringLength := mload(add(input, nextOffset)) // string length MAX 64 so will always be a byte
        }

        ccurrencyDefinition.parent = parent;

        bytes memory name = new bytes(nameStringLength);

        for (uint256 i = 0; i <= nameStringLength; i++) {
            name[i] = input[i + nextOffset];
        }

        ccurrencyDefinition.name = string(name);
        nextOffset = nextOffset + nameStringLength + CCC_LAUNCH_ID_LEN;

        assembly {
            launchSystemID := mload(add(input, nextOffset)) // this should be launchsysemID
        }

        ccurrencyDefinition.launchSystemID = launchSystemID;
    }
}
