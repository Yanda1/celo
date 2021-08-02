# Smart Contract

Yanda Escrow smart contract is built for resolving commission charges between the service provider and customer with the help of validator pull as 3-rd parties.

### Contract on local

Open your favorite Terminal and run these commands.

1. Start Ganache server:
```sh
> ganache-cli --port 7545
```

2. Enter contract dir(separate terminal):
```sh
> cd network
```

3. Apply migrations:
```sh
> truffle migrate --network test
```

4. Start truffle console:
```sh
> truffle console --network test
```

5. Run commands from the example.js:
```js
4  let contract = await YandaEscrow.deployed()
...
7  contract.getState()
...
11 let balance = await web3.eth.getBalance(contract.address)
12 balance
...
16 let accounts = await web3.eth.getAccounts()
...
19 let deposit = await web3.eth.sendTransaction({from: accounts[1], to: contract.address, value: 30})
...
22 balance = await web3.eth.getBalance(contract.address)
23 balance
...
```
