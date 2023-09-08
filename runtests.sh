#!/bin/bash
source .env

# Start ganache-cli in the background 
ganache-cli -l 1500000000 ---account "$PRIVATE_KEY, 100000000000000000000" -p 8545 > "ganache.log" 2>&1 &

# Capture the process ID of ganache-cli
ganache_pid=$!

# Wait for a few seconds to allow ganache-cli to start
sleep 3

# Run Truffle tests
truffle test

# Stop ganache-cli
kill $ganache_pid
