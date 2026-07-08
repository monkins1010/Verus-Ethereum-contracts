// SPDX-License-Identifier: MIT
// Minimal MakerDAO DSR mock for local development/testing.
// These contracts satisfy the PotLike and JoinLike interfaces used by
// VerusCrossChainExport without touching any real MakerDAO infrastructure.

pragma solidity >=0.8.9;

import "../VerusBridge/dsrinterface.sol";

/// @dev Mock DAI Join adapter.  In the real MakerDAO flow, join() pulls DAI
///      from the caller into the VAT.  In our development mock the DAI tokens
///      are already sitting in the Delegator (the delegatecall context), so
///      both join() and exit() are intentional no-ops.
contract MockDaiJoin {

    address public immutable dai;

    constructor(address _dai) {
        dai = _dai;
    }

    /// @dev No-op – tokens are already held by the Delegator in a delegatecall context.
    function join(address /*src*/, uint256 /*wad*/) external {
        // intentional no-op for development
    }

    /// @dev No-op – real exit would send tokens back; not needed in dev testing.
    function exit(address /*dst*/, uint256 /*wad*/) external {
        // intentional no-op for development
    }
}

/// @dev Mock MakerDAO Pot (DAI Savings Rate accumulator).
///      chi is fixed at 1 RAY so the join amount equals the DAI amount.
///      rho() always returns a future timestamp so drip() is never called by
///      the caller (which skips the RAY multiplication).
contract MockPot {

    uint256 constant RAY = 10 ** 27;

    address public immutable vat;       // unused in our mock; kept for interface compat
    uint256 public chi  = RAY;          // 1 RAY → 1:1 conversion
    uint256 public rho  = type(uint256).max; // Always in the future → chi() path taken

    constructor() {
        // vat is unused in our flow; point at address(0) to satisfy the interface
        vat = address(0);
    }

    /// @dev Returns current chi (always 1 RAY in the mock).
    // chi is already declared as a public state var, no extra function needed.

    /// @dev No-op drip – real Pot accrues interest here.
    function drip() external view returns (uint256) {
        return chi;
    }

    /// @dev Accept a pie (DAI share) deposit.  No-op in the mock.
    function join(uint256 /*pie*/) external {
        // nothing to do
    }

    /// @dev Withdraw a pie (DAI share).  No-op in the mock.
    function exit(uint256 /*pie*/) external {
        // nothing to do
    }
}
