## Ethereum Verus contracts

Before compilation an account at https://infura.io/ is needed to allow you to connect to the Ethereum network.

Create a new Ethereum project and choose rinkeby netowork and get a link that looks like this:

https://rinkeby.infura.io/v3/015d792415a734560cd5dbdfeb4  (Dont use this one its invalid)

Then edit the file `truffle-config.js` and edit the infura endpoint, also add in your private key to the private key variable.

To compile all run:

```shell
npm install
npm install -g truffle
truffle compile
truffle deploy --network rinkeby   
```
copy files from ./build/contracts

VerusSerializer.json
VerusProof.json
VerusNotarizer.json
VerusInfo.json
verusBridge.json

To Alan's sub directory directory/abi (these are the Abi files)

Run 
```shell
truffle networks
```
to get a list of the contract addresses:

goto your `/Verustest/pbaas/veth/veth.conf` file and copy in the contract addresses from the above list into the appropriate fields.

Also copy the VerusBridge Contract address into the index.js of the VerusWebsite Dapp, to update that address.
