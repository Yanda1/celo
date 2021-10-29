const Web3 = require('web3');

// Get deployed contract
let contract = await YandaToken.deployed()
console.log('Contract deployed')
// Expected output: Contract deployed

// Check contract balance
let balance = await contract.balanceOf(contract.address)
console.log('Contract balance:', Web3.utils.fromWei(balance, 'ether'))
// Expected output: Contract balance: 0

// Get all accounts
let accounts = await web3.eth.getAccounts()

// Add service from account 1, validator accounts is [2,3,4], validators will get 1/3 and the service 1/3, and the rest will burn
let result = contract.addService(accounts[1], accounts.slice(2, 5), 3, 3)
console.log('Created service for account[1] with 3 validator accounts[2, 3, 4]')
// Expected output: Created service for account[1] with 3 validator accounts[2, 3, 4]

// Transfer 1 YandaToken from token owner to the first validator(accounts[2])
result = await contract.transfer(accounts[2], Web3.utils.toWei('1', 'ether'))

// Transfer 2 YandaToken from token owner to the second validator(accounts[3])
result = await contract.transfer(accounts[3], Web3.utils.toWei('2', 'ether'))

// Transfer 3 YandaToken from token owner to the third validator(accounts[4])
result = await contract.transfer(accounts[4], Web3.utils.toWei('3', 'ether'))

// Transfer 1 YandaToken from token owner to customer account(accounts[5])
result = await contract.transfer(accounts[5], Web3.utils.toWei('1', 'ether'))
balance = await contract.balanceOf(accounts[5])
console.log('Customer balance:', Web3.utils.fromWei(balance, 'ether'))
// Expected output: Customer balance: 1

// Create process for account 5, cost amount is 1 YandaToken, product id: 123 and data is {"a": 1, "b": 2, "c": 3}
result = await contract.createProcess(accounts[1], Web3.utils.toWei('1', 'ether'), Web3.utils.keccak256('123'), '{"a": 1, "b": 2, "c": 3}', {from: accounts[5]})

// Make smart contract deposit from account 5
result = await contract.transfer(contract.address, Web3.utils.toWei('1', 'ether'), {from: accounts[5]})

// Check contract balance
balance = await contract.balanceOf(contract.address)
console.log('Contract balance:', Web3.utils.fromWei(balance, 'ether'))
// Expected output: Contract balance: 1

// Declare few service produced actions
result = await contract.declareAction(accounts[5], Web3.utils.keccak256('123'), 'First order data', {from: accounts[1]})
result = await contract.declareAction(accounts[5], Web3.utils.keccak256('123'), 'Second order data', {from: accounts[1]})

// Start process termination for the productId '123' (service job finished)
result = await contract.startTermination(accounts[5], Web3.utils.keccak256('123'), {from: accounts[1]})
console.log('Service has confirmed product delivery')
// Expected output: Service has confirmed product delivery

// Validator #1 validate termination process for the client accounts[5] with productId "123"
result = await contract.validateTermination(accounts[5], Web3.utils.keccak256('123'), true, {from: accounts[2]});
// Validator #3 validate termination process for the client accounts[5] with productId "123"
result = await contract.validateTermination(accounts[5], Web3.utils.keccak256('123'), true, {from: accounts[4]});
// Validator #2 validate termination process for the client accounts[5] with productId "123"
result = await contract.validateTermination(accounts[5], Web3.utils.keccak256('123'), true, {from: accounts[3]});

// Check contract balance after sending validator reward, service fee and burning the rest
balance = await contract.balanceOf(contract.address)
console.log('Contract balance:', Web3.utils.fromWei(balance, 'ether'))
// Expected output: Contract balance: 0

// Check service balance after sending service fee
balance = await contract.balanceOf(accounts[1])
console.log('Service balance:', Web3.utils.fromWei(balance, 'ether'))
// Expected output: Service balance: 0.333333333333333333

// Check validator #1 balance after receiving validator reward
balance = await contract.balanceOf(accounts[2])
console.log('Validator balance:', Web3.utils.fromWei(balance, 'ether'))
// Expected output: Validator balance: 1.055555555555555555

// Check validator #3 balance after receiving validator reward
balance = await contract.balanceOf(accounts[4])
console.log('Validator balance:', Web3.utils.fromWei(balance, 'ether'))
// Expected output: Validator balance: 3.166666666666666666

// Check validator #2 balance after receiving validator reward
balance = await contract.balanceOf(accounts[3])
console.log('Validator balance:', Web3.utils.fromWei(balance, 'ether'))
// Expected output: Validator balance: 2

// Check token total supply after burning 1/3 of the action cost
let supply = await contract.totalSupply()
console.log('Total supply:', Web3.utils.fromWei(supply, 'ether'))
// Expected output: Total supply: 99999.555555555555555554
