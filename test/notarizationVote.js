/**
 * notarizationVote.js
 *
 * NotarizationSerializer only reads a contract upgrade vote (votetxid) from the proposer's first
 * auxDest when FLAG_CONTRACT_UPGRADE (0x200) is set, and reverts if the flag is set without a
 * DEST_ETH auxDest.
 *
 * Run:  ganache-cli -d, then  truffle test test/notarizationVote.js --to 2
 */

'use strict';

const NotarizationSerializer = artifacts.require('../contracts/VerusNotarizer/NotarizationSerializer.sol');
const notarizationSerializerAbi = require('../build/contracts/NotarizationSerializer.json');
const testNotarization = require('./submitnotarization.js');

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

// version 02, flags varint 85 0c (0x30c, includes FLAG_CONTRACT_UPGRADE), proposer DEST_PKH|AUX
const VOTE_NOTARIZATION = testNotarization.firstNotarization;
const FLAGS_WITH_UPGRADE = '02850c';
const FLAGS_WITHOUT_UPGRADE = '02810c';
const PKH_AUX_PROPOSER_PREFIX = '4214';
const VOTE_ADDRESS = '9304c78dd2c478a5cd5841dd751dc16baa320603';
// auxDest vector: count 1, length 0x16, DEST_ETH (09), length 0x14, address
const ETH_AUX = '011609149304c78dd2c478a5cd5841dd751dc16baa320603';

contract('Notarization contract upgrade vote', async () => {

    let serializer;

    const parse = (hex) => serializer.methods.deserializeNotarization(hex).call();

    const expectRevert = async (hex) => {
        try {
            await parse(hex);
        } catch (e) {
            assert.include(e.message, 'contract upgrade requires DEST_ETH auxdest');
            return;
        }
        assert.fail('expected revert');
    };

    before(async () => {
        const deployed = await NotarizationSerializer.deployed();
        serializer = new web3.eth.Contract(notarizationSerializerAbi.abi, deployed.address);
    });

    it('fixture has the expected layout', () => {
        assert.isTrue(VOTE_NOTARIZATION.startsWith('0x' + FLAGS_WITH_UPGRADE + PKH_AUX_PROPOSER_PREFIX));
        assert.include(VOTE_NOTARIZATION, ETH_AUX);
    });

    it('returns the vote address when the flag is set and the first auxDest is DEST_ETH', async () => {
        const result = await parse(VOTE_NOTARIZATION);
        assert.equal(result.votetxid.toLowerCase(), '0x' + VOTE_ADDRESS);
    });

    it('ignores the auxDest when the flag is not set', async () => {
        const noFlag = VOTE_NOTARIZATION.replace('0x' + FLAGS_WITH_UPGRADE, '0x' + FLAGS_WITHOUT_UPGRADE);
        const result = await parse(noFlag);
        assert.equal(result.votetxid, ZERO_ADDRESS);
    });

    it('reverts when the flag is set but the first auxDest is not DEST_ETH', async () => {
        // DEST_PKH (02) instead of DEST_ETH (09)
        const wrongType = VOTE_NOTARIZATION.replace(ETH_AUX, '011602149304c78dd2c478a5cd5841dd751dc16baa320603');
        assert.notEqual(wrongType, VOTE_NOTARIZATION);
        await expectRevert(wrongType);
    });

    it('reverts when the flag is set but the proposer has no auxDest', async () => {
        const proposerWithAux = PKH_AUX_PROPOSER_PREFIX + VOTE_NOTARIZATION.split(PKH_AUX_PROPOSER_PREFIX)[1].slice(0, 40) + ETH_AUX;
        assert.include(VOTE_NOTARIZATION, proposerWithAux);
        const noAux = VOTE_NOTARIZATION.replace(proposerWithAux, '0214' + proposerWithAux.slice(4, 44));
        await expectRevert(noAux);
    });

    it('reverts when the flag is set and the auxDest vector is empty', async () => {
        const emptyAux = VOTE_NOTARIZATION.replace(ETH_AUX, '00');
        await expectRevert(emptyAux);
    });
});
