#!/bin/bash
# Run only the deployed.js test suite against a fresh non-persistent ganache (development network).
# Contracts are deployed via migrations 1 and 2 before the tests run.

ganache-cli -l 1500000000 -p 8545 > ganache-deployed.log 2>&1 &
ganache_pid=$!

sleep 3

truffle test test/deployed.js --stacktrace --to 2

kill $ganache_pid
