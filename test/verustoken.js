/**
 * VerusToken unit tests
 *
 * Scenario:
 *   - Deploy VerusToken with 3 000 000 VRT and a 3 ETH restitution target.
 *   - Distribute exactly 33 % (1 000 000 VRT) to each of three users.
 *   - Donate 1 ETH to the contract.
 *   - Verify that a user who redeems their 33 % of supply receives 33 % of the ETH.
 *
 * Run with:  truffle test ./test/verustoken.js
 */

const VerusToken = artifacts.require("../contracts/Token/VerusToken.sol");

const { toBN, toWei } = web3.utils;

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Calculate the gas cost of a Truffle transaction receipt in wei.
 * @param {object} receipt  Truffle transaction result.
 * @returns {BN}
 */
async function gasCostOf(receipt) {
    const tx = await web3.eth.getTransaction(receipt.tx);
    return toBN(receipt.receipt.gasUsed).mul(toBN(tx.gasPrice));
}

// ── Constants ─────────────────────────────────────────────────────────────────

const TOTAL_SUPPLY = toWei("3000000"); // 3 000 000 VRT (18 dp)
const TARGET_ETH   = toWei("3");       // 3 ETH → full 1-to-1 restitution
const ONE_THIRD    = toWei("1000000"); // 1 000 000 VRT = 33.333…%
const FUND_1_ETH   = toWei("1");       // initial donation

// ── Test suite ────────────────────────────────────────────────────────────────

contract("VerusToken", (accounts) => {
    const [deployer, user1, user2, user3] = accounts;

    let token;

    // Deploy a fresh contract before every test.
    beforeEach(async () => {
        token = await VerusToken.new(TOTAL_SUPPLY, TARGET_ETH, { from: deployer });
    });

    // ── Deployment ────────────────────────────────────────────────────────────

    describe("Deployment", () => {
        it("records the correct original supply", async () => {
            const original = await token.originalSupply();
            assert.equal(original.toString(), TOTAL_SUPPLY, "originalSupply mismatch");
        });

        it("records the correct target ETH", async () => {
            const target = await token.targetEth();
            assert.equal(target.toString(), TARGET_ETH, "targetEth mismatch");
        });

        it("mints the entire supply to the deployer", async () => {
            const balance = await token.balanceOf(deployer);
            assert.equal(balance.toString(), TOTAL_SUPPLY, "deployer balance mismatch");
        });

        it("total supply equals TOTAL_SUPPLY", async () => {
            const supply = await token.totalSupply();
            assert.equal(supply.toString(), TOTAL_SUPPLY, "totalSupply mismatch");
        });

        it("contract ETH balance starts at zero", async () => {
            const eth = await web3.eth.getBalance(token.address);
            assert.equal(eth.toString(), "0", "initial ETH balance should be 0");
        });
    });

    // ── Token distribution ────────────────────────────────────────────────────

    describe("Token distribution (33 % to each of three users)", () => {
        beforeEach(async () => {
            await token.transfer(user1, ONE_THIRD, { from: deployer });
            await token.transfer(user2, ONE_THIRD, { from: deployer });
            await token.transfer(user3, ONE_THIRD, { from: deployer });
        });

        it("user1 receives 33 % of total supply", async () => {
            const bal = await token.balanceOf(user1);
            assert.equal(bal.toString(), ONE_THIRD, "user1 balance wrong");
        });

        it("user2 receives 33 % of total supply", async () => {
            const bal = await token.balanceOf(user2);
            assert.equal(bal.toString(), ONE_THIRD, "user2 balance wrong");
        });

        it("user3 receives 33 % of total supply", async () => {
            const bal = await token.balanceOf(user3);
            assert.equal(bal.toString(), ONE_THIRD, "user3 balance wrong");
        });

        it("deployer holds no tokens after distribution", async () => {
            const bal = await token.balanceOf(deployer);
            assert.equal(bal.toString(), "0", "deployer should hold 0 tokens");
        });

        it("total supply is unchanged after transfers", async () => {
            const supply = await token.totalSupply();
            assert.equal(supply.toString(), TOTAL_SUPPLY, "totalSupply should not change on transfer");
        });
    });

    // ── ETH donation ──────────────────────────────────────────────────────────

    describe("ETH donation via receive()", () => {
        it("accepts ETH and updates contract balance", async () => {
            await web3.eth.sendTransaction({
                from: deployer,
                to: token.address,
                value: FUND_1_ETH,
            });
            const eth = await web3.eth.getBalance(token.address);
            assert.equal(eth.toString(), FUND_1_ETH, "contract ETH balance wrong after donation");
        });

        it("accepts multiple donations and accumulates balance", async () => {
            await web3.eth.sendTransaction({ from: deployer, to: token.address, value: FUND_1_ETH });
            await web3.eth.sendTransaction({ from: user1,    to: token.address, value: FUND_1_ETH });
            const eth = await web3.eth.getBalance(token.address);
            assert.equal(
                eth.toString(),
                toBN(FUND_1_ETH).mul(toBN("2")).toString(),
                "accumulated ETH balance wrong"
            );
        });
    });

    // ── Redemption (core scenario) ────────────────────────────────────────────

    describe("Redemption: 1 ETH in contract, user redeems 33 % of supply", () => {
        // Expected ETH per 1/3-supply redemption:
        //   1 000 000 × min(1 ETH, 3 ETH) / 3 000 000 = 1/3 ETH
        const EXPECTED_ETH = toBN(FUND_1_ETH).div(toBN("3")); // 333 333 333 333 333 333 wei

        beforeEach(async () => {
            // Distribute tokens
            await token.transfer(user1, ONE_THIRD, { from: deployer });
            await token.transfer(user2, ONE_THIRD, { from: deployer });
            await token.transfer(user3, ONE_THIRD, { from: deployer });

            // Fund contract with 1 ETH
            await web3.eth.sendTransaction({
                from: deployer,
                to: token.address,
                value: FUND_1_ETH,
            });
        });

        it("calculateRedemption preview equals 1/3 ETH", async () => {
            const preview = await token.calculateRedemption(ONE_THIRD);
            assert.equal(
                preview.toString(),
                EXPECTED_ETH.toString(),
                "calculateRedemption returned wrong value"
            );
        });

        it("fundingProgress returns correct current and target", async () => {
            const { current, target } = await token.fundingProgress();
            assert.equal(current.toString(), FUND_1_ETH, "current ETH wrong");
            assert.equal(target.toString(),  TARGET_ETH,  "target ETH wrong");
        });

        // ── Auto-redeem via transfer to contract address ──────────────────────

        it("user1 sends tokens to contract address and receives 1/3 ETH (auto-redeem)", async () => {
            const ethBefore = toBN(await web3.eth.getBalance(user1));

            const receipt = await token.transfer(token.address, ONE_THIRD, { from: user1 });

            const cost     = await gasCostOf(receipt);
            const ethAfter = toBN(await web3.eth.getBalance(user1));

            // Net ETH gain = (after + gas) - before
            const gained = ethAfter.add(cost).sub(ethBefore);

            assert.equal(
                gained.toString(),
                EXPECTED_ETH.toString(),
                "user1 ETH gain after auto-redeem is wrong"
            );
        });

        it("user1 token balance is zero after auto-redeem", async () => {
            await token.transfer(token.address, ONE_THIRD, { from: user1 });
            const bal = await token.balanceOf(user1);
            assert.equal(bal.toString(), "0", "user1 token balance should be 0 after redeem");
        });

        it("total supply decreases by the redeemed amount (tokens are burnt)", async () => {
            await token.transfer(token.address, ONE_THIRD, { from: user1 });
            const supply = await token.totalSupply();
            const expected = toBN(TOTAL_SUPPLY).sub(toBN(ONE_THIRD));
            assert.equal(supply.toString(), expected.toString(), "totalSupply after burn wrong");
        });

        it("contract ETH balance decreases by the amount sent to user1", async () => {
            await token.transfer(token.address, ONE_THIRD, { from: user1 });
            const contractEth = await web3.eth.getBalance(token.address);
            const expected = toBN(FUND_1_ETH).sub(EXPECTED_ETH);
            assert.equal(contractEth.toString(), expected.toString(), "contract ETH after redeem wrong");
        });

        // ── Explicit redeem() ─────────────────────────────────────────────────

        it("user1 can redeem via the explicit redeem() function", async () => {
            const ethBefore = toBN(await web3.eth.getBalance(user1));

            const receipt  = await token.redeem(ONE_THIRD, { from: user1 });
            const cost     = await gasCostOf(receipt);
            const ethAfter = toBN(await web3.eth.getBalance(user1));

            const gained = ethAfter.add(cost).sub(ethBefore);

            assert.equal(
                gained.toString(),
                EXPECTED_ETH.toString(),
                "user1 ETH gain via redeem() is wrong"
            );
        });

        it("reverts if user tries to redeem 0 tokens", async () => {
            try {
                await token.redeem("0", { from: user1 });
                assert.fail("expected revert");
            } catch (err) {
                assert.include(err.message, "amount must be > 0", "wrong revert reason");
            }
        });
    });

    // ── Full restitution (3 ETH = target) ─────────────────────────────────────

    describe("Full restitution: contract funded to target (3 ETH)", () => {
        beforeEach(async () => {
            await token.transfer(user1, ONE_THIRD, { from: deployer });
            await token.transfer(user2, ONE_THIRD, { from: deployer });
            await token.transfer(user3, ONE_THIRD, { from: deployer });

            await web3.eth.sendTransaction({
                from: deployer,
                to: token.address,
                value: TARGET_ETH, // 3 ETH = full target
            });
        });

        it("user1 (33 %) redeems and gets exactly 1 ETH back (1-to-1 restitution)", async () => {
            const ethBefore = toBN(await web3.eth.getBalance(user1));

            const receipt  = await token.transfer(token.address, ONE_THIRD, { from: user1 });
            const cost     = await gasCostOf(receipt);
            const ethAfter = toBN(await web3.eth.getBalance(user1));

            const gained = ethAfter.add(cost).sub(ethBefore);

            assert.equal(
                gained.toString(),
                FUND_1_ETH, // 1 ETH = 1 000 000 / 3 000 000 × 3 ETH
                "user1 should receive exactly 1 ETH at full funding"
            );
        });

        it("calculateRedemption returns 1 ETH for 1/3 of supply at full funding", async () => {
            const preview = await token.calculateRedemption(ONE_THIRD);
            assert.equal(preview.toString(), FUND_1_ETH, "preview at full funding wrong");
        });
    });

    // ── Over-funded (more ETH than target) ────────────────────────────────────

    describe("Over-funded: contract holds more ETH than the restitution target", () => {
        const OVER_FUND = toWei("6"); // 6 ETH – twice the 3 ETH target

        beforeEach(async () => {
            await token.transfer(user1, ONE_THIRD, { from: deployer });
            await token.transfer(user2, ONE_THIRD, { from: deployer });
            await token.transfer(user3, ONE_THIRD, { from: deployer });

            await web3.eth.sendTransaction({
                from: deployer,
                to: token.address,
                value: OVER_FUND,
            });
        });

        it("calculateRedemption reflects full actual balance (no cap)", async () => {
            // 1M / 3M × 6 ETH = 2 ETH
            const expected = toBN(OVER_FUND).div(toBN("3"));
            const preview  = await token.calculateRedemption(ONE_THIRD);
            assert.equal(preview.toString(), expected.toString(), "preview should reflect uncapped balance");
        });

        it("user1 (33 %) redeems and receives 2 ETH when contract holds 6 ETH", async () => {
            const ethBefore = toBN(await web3.eth.getBalance(user1));

            const receipt  = await token.transfer(token.address, ONE_THIRD, { from: user1 });
            const cost     = await gasCostOf(receipt);
            const ethAfter = toBN(await web3.eth.getBalance(user1));

            const gained   = ethAfter.add(cost).sub(ethBefore);
            const expected = toBN(OVER_FUND).div(toBN("3")); // 2 ETH

            assert.equal(gained.toString(), expected.toString(), "should receive proportional share of over-funded balance");
        });
    });

    // ── Partial redemptions: holding longer earns more ───────────────────────
    //
    // Scenario
    //   user1 holds 1 000 000 VRT (33 % of supply).
    //   Contract starts with 1 ETH.
    //
    //   Step 1 – user1 burns 100 000 VRT (10 % of their bag).
    //            Contract has 1 ETH  → payout = 100K × 1 ETH / 3M = ~0.0333 ETH
    //
    //   Step 2 – someone donates 2 more ETH.
    //            Contract now has (1 - 0.0333) + 2 ≈ 2.9667 ETH
    //
    //   Step 3 – user1 burns another 100 000 VRT (10 % of original bag).
    //            Contract has ~2.9667 ETH → payout ≈ 100K × 2.9667 ETH / 3M ≈ 0.0989 ETH
    //
    //   → The second burn of the same token quantity yields ~3× more ETH,
    //     demonstrating that holding and waiting for more donations is rewarded.

    describe("Partial redemptions: holding longer earns more ETH per token", () => {
        const ONE_TENTH_OF_USER = toWei("100000"); // 100 000 VRT = 10 % of user1's 1 M bag
        const TOPUP_ETH         = toWei("2");      // additional 2 ETH donated between redeems

        beforeEach(async () => {
            await token.transfer(user1, ONE_THIRD, { from: deployer });
            await token.transfer(user2, ONE_THIRD, { from: deployer });
            await token.transfer(user3, ONE_THIRD, { from: deployer });

            // Initial funding: 1 ETH
            await web3.eth.sendTransaction({
                from: deployer,
                to: token.address,
                value: FUND_1_ETH,
            });
        });

        it("first partial redeem (10 % of bag, 1 ETH in contract) returns ~0.0333 ETH", async () => {
            // expected = 100 000 × 1 ETH / 3 000 000 = 33 333 333 333 333 333 wei
            const expected = toBN(ONE_TENTH_OF_USER).mul(toBN(FUND_1_ETH)).div(toBN(TOTAL_SUPPLY));

            const ethBefore = toBN(await web3.eth.getBalance(user1));
            const receipt   = await token.transfer(token.address, ONE_TENTH_OF_USER, { from: user1 });
            const cost      = await gasCostOf(receipt);
            const ethAfter  = toBN(await web3.eth.getBalance(user1));
            const gained    = ethAfter.add(cost).sub(ethBefore);

            assert.equal(gained.toString(), expected.toString(),
                "first partial redeem ETH payout wrong");
        });

        it("second partial redeem (10 % of bag, after 2 ETH top-up) returns ~0.0989 ETH — ~3× the first", async () => {
            // ── First burn ──────────────────────────────────────────────────────
            const ethGained1 = toBN(ONE_TENTH_OF_USER).mul(toBN(FUND_1_ETH)).div(toBN(TOTAL_SUPPLY));
            await token.transfer(token.address, ONE_TENTH_OF_USER, { from: user1 });

            // ── Top-up ──────────────────────────────────────────────────────────
            await web3.eth.sendTransaction({
                from: deployer,
                to: token.address,
                value: TOPUP_ETH,
            });

            // Contract ETH before second burn:
            //   (1 ETH - ethGained1) + 2 ETH
            const contractEthNow = toBN(FUND_1_ETH).sub(ethGained1).add(toBN(TOPUP_ETH));

            // Expected second payout:
            //   100 000 × contractEthNow / 3 000 000
            const ethGained2Expected = toBN(ONE_TENTH_OF_USER).mul(contractEthNow).div(toBN(TOTAL_SUPPLY));

            // ── Second burn ─────────────────────────────────────────────────────
            const ethBefore = toBN(await web3.eth.getBalance(user1));
            const receipt   = await token.transfer(token.address, ONE_TENTH_OF_USER, { from: user1 });
            const cost      = await gasCostOf(receipt);
            const ethAfter  = toBN(await web3.eth.getBalance(user1));
            const ethGained2 = ethAfter.add(cost).sub(ethBefore);

            assert.equal(ethGained2.toString(), ethGained2Expected.toString(),
                "second partial redeem ETH payout wrong");

            // Core assertion: waiting through the top-up pays off
            assert.ok(
                ethGained2.gt(ethGained1),
                `holding paid off: second redeem (${ethGained2} wei) > first redeem (${ethGained1} wei)`
            );
        });

        it("user1 token balance decrements correctly after two partial redeems", async () => {
            await token.transfer(token.address, ONE_TENTH_OF_USER, { from: user1 });
            await web3.eth.sendTransaction({ from: deployer, to: token.address, value: TOPUP_ETH });
            await token.transfer(token.address, ONE_TENTH_OF_USER, { from: user1 });

            const remaining = await token.balanceOf(user1);
            // Started with 1 000 000, burnt 100 000 twice = 800 000 left
            const expected = toBN(ONE_THIRD).sub(toBN(ONE_TENTH_OF_USER).mul(toBN("2")));
            assert.equal(remaining.toString(), expected.toString(),
                "user1 remaining token balance wrong after two partial redeems");
        });
    });

    // ── Edge case: no ETH yet ─────────────────────────────────────────────────

    describe("Edge case: redemption before any ETH is donated", () => {
        it("reverts when no ETH is in the contract", async () => {
            await token.transfer(user1, ONE_THIRD, { from: deployer });
            try {
                await token.transfer(token.address, ONE_THIRD, { from: user1 });
                assert.fail("expected revert");
            } catch (err) {
                assert.include(err.message, "no ETH in contract yet", "wrong revert reason");
            }
        });
    });
});
