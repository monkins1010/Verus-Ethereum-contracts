## Ethereum Verus contracts

Before compilation an account at https://infura.io/ is needed to allow you to connect to the Ethereum network.

Create a new Ethereum project and choose rinkeby netowork and get a link that looks like this:

https://rinkeby.infura.io/v3/015d792415a734560cd5dbdfeb4  (Dont use this one its invalid)

Then edit the file `truffle-config.js` and edit the infura endpoint, also add in your private key to the private key variable.

To compile all run:

```shell
npm install
npm install -g truffle@5.3.14
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

## Running Truffle Tests

To run the automated tests, your private key needs to be set in a .env file in the root folder as

```
GANACHE_KEY=32198a9bbb9.... #32 bye key without the 0x
```
This Key has to be one of the Notaries Spending Keys.

Then to run the tests run:
```shell
npm run test
```

## Update 21st July 2023
- Added truffle tests

## Update 11th May 2022

- Truffle version must be no newer than 5.3.14
- Set contracts TokenManger.sol must be initialized with setContracts() after its updated.
