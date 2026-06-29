// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title VerusUsageToken – ERC-20
 *
 * Mechanics
 * ---------
 * • A fixed supply is minted to the deployer at construction.
 * • Anyone can donate ETH to this contract at any time (plain ETH send).
 * • Token holders can redeem their tokens for a proportional share of the
 *   ETH currently held by the contract at the time of redemption.
 *
 *   ETH returned = tokenAmount × contractETH / originalSupply
 *
 *   If more ETH is donated than the original target the excess is shared
 *   proportionally – there is no upper cap on the redemption amount.
 *
 * • Redemption happens automatically when a user transfers tokens directly
 *   to this contract address (e.g. MetaMask's normal "Send" flow), so no
 *   separate approve+call is needed.
 * • Alternatively, the explicit `redeem(amount)` function can be used.
 *
 * There is no owner; the contract is fully autonomous after deployment.
 */
contract VerusUsageToken is ERC20, ReentrancyGuard {
    /// @notice Total tokens minted at deployment.
    uint256 public supply;

    event TokensRedeemed(address indexed redeemer, uint256 tokenAmount, uint256 ethAmount);
    event EthDonated(address indexed donor, uint256 amount);

    /**
     * @param initialSupply Tokens to mint, expressed in base units (include decimals).
     *                      Example: 1 000 000 tokens with 18 dp = 1_000_000 * 1e18.
     */
    constructor(uint256 initialSupply)
        ERC20("Verus Usage Token", "VUT")
    {
        require(initialSupply > 0, "VerusUsageToken: supply must be > 0");
        supply = initialSupply;
        _mint(msg.sender, initialSupply);
    }

    // -------------------------------------------------------------------------
    // ETH donation
    // -------------------------------------------------------------------------

    /// @dev Accept plain ETH transfers (donations).
    receive() external payable {
        emit EthDonated(msg.sender, msg.value);
    }

    // -------------------------------------------------------------------------
    // Auto-redemption: tokens sent directly to this contract address are burnt
    // and the proportional ETH share is returned to the sender.
    // -------------------------------------------------------------------------

    /**
     * @dev Overrides ERC-20 `transfer` so that sending tokens to this contract's
     *      address (e.g. from MetaMask) triggers auto-redemption instead of
     *      locking them forever.
     */
    function transfer(address to, uint256 amount) public override nonReentrant returns (bool) {
        if (to == address(this)) {
            _redeem(msg.sender, amount);
            return true;
        }
        return super.transfer(to, amount);
    }

    // -------------------------------------------------------------------------
    // Explicit redemption
    // -------------------------------------------------------------------------

    /**
     * @notice Burn `amount` of your tokens and receive the proportional ETH share.
     * @param amount Token base units to redeem.
     */
    function redeem(uint256 amount) external nonReentrant {
        _redeem(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    /**
     * @dev Core redemption logic.
     *      Burns `tokenAmount` from `redeemer` and transfers the ETH share.
     *
     *      ETH returned = tokenAmount × contractETH / originalSupply
     *
     *      There is no upper cap: if more ETH has been donated than the original
     *      target, holders receive their proportional share of the larger balance.
     *
     *      Reverts if there is no ETH in the contract (protects users who
     *      accidentally trigger the auto-redeem path before any ETH is donated).
     */
    function _redeem(address redeemer, uint256 tokenAmount) internal {
        require(tokenAmount > 0, "VerusUsageToken: amount must be > 0");

        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "VerusUsageToken: no ETH in contract yet");

        // Use mulDiv for overflow safety (OZ Math, rounds down).
        uint256 ethToSend = Math.mulDiv(tokenAmount, ethBalance, supply);
        supply -= tokenAmount;  // reduce supply to reflect burnt tokens

        // Guard against dust: if the token amount is so small that the integer
        // division rounds to zero, revert rather than burning tokens for nothing.
        require(ethToSend > 0, "VerusUsageToken: redemption rounds to zero");

        // Burn first (state change before external call – Checks-Effects-Interactions).
        _burn(redeemer, tokenAmount);

        // slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(redeemer).call{value: ethToSend}("");
        require(success, "VerusUsageToken: ETH transfer failed");

        emit TokensRedeemed(redeemer, tokenAmount, ethToSend);
    }
}
