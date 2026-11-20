// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IFlowView {
    function claimableFees(bytes32 key) external view returns (uint256);
}

/// @dev TEST ONLY. A hostile ERC-20: when armed, its transfer() and transferFrom() first make a list of calls chosen
///      by the test (back into the Delegator, or straight at a logic contract), then move the tokens as normal.
///      It runs while the bridge is in the middle of a flow (SEND_TRANSFER for a deposit, EXECUTE_IMPORT for a
///      payout), so it shows what a token callback can reach with that flow active. Results go in one word:
///      record = 2 | flowSeen << 8 | successBitmap << 16 (bit i set = call i succeeded); 1 = armed with the stored
///      list, 3 = armed with the built-in payout list. The payout list is built in code, not read from storage, so
///      the hook fits in the 100,000 gas an import payout gives a token.
///      Never deploy to production.
contract MockReentrantToken is ERC20 {

    bytes32 constant FLOW_KEY = keccak256("veth.internal.call.flow");

    address immutable DELEGATOR;
    uint256 public record = 2;
    address importsTarget;
    address[] targets;
    bytes[] calls;
    uint256[] values;

    constructor(address delegator, address holder, uint256 supply) ERC20("Hostile", "HOST") {
        DELEGATOR = delegator;
        _mint(holder, supply);
    }

    receive() external payable {}

    function arm(address[] calldata _targets, bytes[] calldata _calls, uint256[] calldata _values) external {
        delete targets;
        delete calls;
        delete values;
        for (uint256 i = 0; i < _calls.length; i++) {
            targets.push(_targets[i]);
            calls.push(_calls[i]);
            values.push(_values[i]);
        }
        record = 1;
    }

    /// Built-in list for a payout: two setVerusData routes and a direct call to Imports.payOutImport.
    function armPayout(address imports) external {
        importsTarget = imports;
        record = 3;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _reenter();
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _reenter();
        return super.transferFrom(from, to, amount);
    }

    function _reenter() private {
        uint256 mode = record;
        if (mode != 1 && mode != 3) return;
        record = 2;     // disarm first, so a nested call back into this token does not run the list again
        uint256 flow = IFlowView(DELEGATOR).claimableFees(FLOW_KEY);
        uint256 succeeded;
        bool ok;
        if (mode == 1) {
            for (uint256 i = 0; i < calls.length; i++) {
                (ok,) = targets[i].call{value: values[i]}(calls[i]);
                if (ok) succeeded |= 1 << i;
            }
        } else {
            (ok,) = DELEGATOR.call(abi.encodeWithSignature("setVerusData(bytes,string)", bytes(""), "payOutImport"));
            if (ok) succeeded |= 1;
            (ok,) = DELEGATOR.call(abi.encodeWithSignature("setVerusData(bytes,string)",
                abi.encode(bytes32(uint256(1)), true), "approveOrRejectAcceptedImport"));
            if (ok) succeeded |= 2;
            (ok,) = importsTarget.call(abi.encodeWithSignature("payOutImport(address,address,uint64)",
                address(this), address(0), uint64(1)));
            if (ok) succeeded |= 4;
        }
        record = 2 | flow << 8 | succeeded << 16;
    }
}
