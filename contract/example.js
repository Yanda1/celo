const Web3 = require('web3');

// Get deployed contract
let contract = await YandaToken.deployed()
console.log('Contract deployed')

// Check contract balance
let balance = await contract.balanceOf(contract.address)
console.log('Contract balance:', Web3.utils.fromWei(balance, 'ether'))
// Contract balance: 0

// Get all accounts
let accounts = await web3.eth.getAccounts()

// Add service from account 1, validator accounts is [2,3,4], validators will get 1/3 and the service 1/3, and the rest will burn
contract.addService(accounts[1], accounts.slice(2, 5), 3, 3)
console.log('Created service for account[1] with 3 validator accounts[2, 3, 4]')

// Transfer 1 YandaToken from token owner to customer account(accounts[5])
let transact = await contract.transfer(accounts[5], Web3.utils.toWei('1', 'ether'))
balance = await contract.balanceOf(accounts[5])
console.log('Customer balance:', Web3.utils.fromWei(balance, 'ether'))
// Exp output: Customer balance: 1

// Create payment process for account 5, cost amount is 1 ether, object id 123
transact = await contract.createProcess(accounts[1], Web3.utils.toWei('1', 'ether'), '123', {from: accounts[5]})
console.log('Created process for account[5] and deposit 1 ether')

// Make deposit from account 5
transact = await contract.transfer(contract.address, Web3.utils.toWei('1', 'ether'), {from: accounts[5]})

// Check contract balance
balance = await contract.balanceOf(contract.address)
console.log('Contract balance:', Web3.utils.fromWei(balance, 'ether'))
// Exp output: Contract balance: 1

// Declare few service produced actions(service finished)
contract.declareAction(accounts[5], '123', 'First order data', {from: accounts[1]})
contract.declareAction(accounts[5], '123', 'Second order data', {from: accounts[1]})

// Start contract termination(service finished)
contract.startTermination(accounts[5], {from: accounts[1]})
console.log('Service has confirmed product delivery')

// Validate termination with the same fee value that was passed by the service 
contract.validateTermination(accounts[5], true, {from: accounts[2]});
console.log('account[2] validated accounts[5] process, waiting for others...')
contract.validateTermination(accounts[5], true, {from: accounts[3]});
console.log('account[3] validated accounts[5] process, waiting for others...')

// Check contract balance after sending validator reward, service fee and burning the rest
balance = await contract.balanceOf(contract.address)
console.log('Contract balance:', Web3.utils.fromWei(balance, 'ether'))
// Exp output: Contract balance: 0

// Check service balance after sending service fee
balance = await contract.balanceOf(accounts[1])
console.log('Service balance:', Web3.utils.fromWei(balance, 'ether'))
// Exp output: Service balance: 0.333333333333333333

// Check one of 3 validators balance after sending validator reward
balance = await contract.balanceOf(accounts[2])
console.log('Validator balance:', Web3.utils.fromWei(balance, 'ether'))
// Exp output: Validator balance: 0.111111111111111111

// Check token total supply after burning 1/3 of the action cost
let supply = await contract.totalSupply()
console.log('Total supply:', Web3.utils.fromWei(supply, 'ether'))
// Exp output: Total supply: 99999.666666666666666666
