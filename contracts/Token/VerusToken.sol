// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title VerusToken – Restitution ERC-20
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
contract VerusToken is ERC20, ReentrancyGuard {
    /// @notice Total tokens minted at deployment – never changes.
    uint256 public immutable originalSupply;

    /// @notice Total ETH (wei) that represents complete 1-to-1 restitution.
    uint256 public immutable targetEth;

    event TokensRedeemed(address indexed redeemer, uint256 tokenAmount, uint256 ethAmount);
    event EthDonated(address indexed donor, uint256 amount);

    /**
     * @param initialSupply Tokens to mint, expressed in base units (include decimals).
     *                      Example: 1 000 000 tokens with 18 dp = 1_000_000 * 1e18.
     * @param targetEthAmount Total ETH in wei for full restitution.
     *                        Example: 3 ETH = 3e18.
     */
    constructor(uint256 initialSupply, uint256 targetEthAmount)
        ERC20("Verus Restitution Token", "VRT")
    {
        require(initialSupply > 0, "VerusToken: supply must be > 0");
        require(targetEthAmount > 0, "VerusToken: target ETH must be > 0");
        originalSupply = initialSupply;
        targetEth = targetEthAmount;
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

    /**
     * @dev Overrides ERC-20 `transferFrom` for the same auto-redemption path.
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        nonReentrant
        returns (bool)
    {
        if (to == address(this)) {
            _spendAllowance(from, msg.sender, amount);
            _redeem(from, amount);
            return true;
        }
        return super.transferFrom(from, to, amount);
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
    // View helpers
    // -------------------------------------------------------------------------

    /**
     * @notice Preview how much ETH `tokenAmount` would currently return.
     * @param tokenAmount Token base units.
     * @return ethAmount ETH in wei that would be sent.
     */
    function calculateRedemption(uint256 tokenAmount) external view returns (uint256 ethAmount) {
        ethAmount = Math.mulDiv(tokenAmount, address(this).balance, originalSupply);
    }

    /**
     * @notice Returns the current ETH balance and the target ETH for full restitution.
     * @return current Contract ETH balance in wei.
     * @return target  Target ETH in wei (set at construction).
     */
    function fundingProgress() external view returns (uint256 current, uint256 target) {
        return (address(this).balance, targetEth);
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
        require(tokenAmount > 0, "VerusToken: amount must be > 0");

        uint256 ethBalance = address(this).balance;
        require(ethBalance > 0, "VerusToken: no ETH in contract yet");

        // Use mulDiv for overflow safety (OZ Math, rounds down).
        uint256 ethToSend = Math.mulDiv(tokenAmount, ethBalance, originalSupply);

        // Guard against dust: if the token amount is so small that the integer
        // division rounds to zero, revert rather than burning tokens for nothing.
        require(ethToSend > 0, "VerusToken: redemption rounds to zero");

        // Burn first (state change before external call – Checks-Effects-Interactions).
        _burn(redeemer, tokenAmount);

        // slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(redeemer).call{value: ethToSend}("");
        require(success, "VerusToken: ETH transfer failed");

        emit TokensRedeemed(redeemer, tokenAmount, ethToSend);
    }
}
