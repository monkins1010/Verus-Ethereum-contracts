#!/bin/bash
# Run the pending-import lifecycle integration test in isolation.
# Uses -d (deterministic accounts) so notary signer addresses are stable.
# The halt tests at the end of the suite permanently pause the bridge in this
# session, so this test is intentionally run separately from runtests-deployed.sh.

ganache-cli -l 1500000000 -p 8545 -d > ganache-lifecycle.log 2>&1 &
ganache_pid=$!

sleep 3

truffle test test/pendingImports.lifecycle.js --stacktrace --to 2

kill $ganache_pid
