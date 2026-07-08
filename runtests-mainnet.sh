#!/bin/bash
# Run only the checkExportAndTransfers.mainnet.js test suite.
# The test deploys VerusProof directly with mainnet contract addresses so no forked
# network is needed — a plain development ganache is sufficient.

ganache-cli -l 1500000000 -p 8545 > ganache-mainnet.log 2>&1 &
ganache_pid=$!

sleep 3

truffle test test/checkExportAndTransfers.mainnet.js --stacktrace --to 2

kill $ganache_pid
