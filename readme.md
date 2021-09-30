##Ethereum Verus contracts

To compile all run:

npm install

npm install -g truffle

truffle compile

truffle deploy --network rinkeby   

copy files from ./build/contracts

VerusSerializer.json
VerusProof.json
VerusNotarizer.json
VerusInfo.json
verusBridge.json

To Alan's home directory (these are the Abi files)

Run 

`truffle networks`

to get a list of the contract addresses:

goto you /Verustest/pbaas/veth/veth.conf file and copy in the contract addresses from the above list into the appropriate fields.

Also copy the VerusBridge Contract address into teh index.js of the VerusWebsite Dapp, to update that address.