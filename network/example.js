const Web3 = require('web3');

// Get deployed contract
let contract = await YandaToken.deployed()
console.log('Contract deployed')

// Check contract balance
let balance = await contract.balanceOf(contract.address)
console.log('Contract balance:', balance.toString())
// Contract balance: 0

// Get all accounts
let accounts = await web3.eth.getAccounts()

// Add service from account 1, validator accounts is [2,3,4], validators will get 1/3 and the service 1/3
contract.addService(accounts[1], accounts.slice(2, 5), 3, 3)
console.log('Created service for account[1] with 3 validator accounts[2, 3, 4]')

// Create payment process for account 5, bill amount is 1 ether, object id 1
contract.addProcess(accounts[5], Web3.utils.toWei('1', 'ether'), 1, {from: accounts[1]})
console.log('Created process for account[5] with 1 ether bill')

// Transfer 1 YandaToken from token owner to customer account(accounts[5])
let transfer = await contract.transfer(accounts[5], Web3.utils.toWei('1', 'ether'))
balance = await contract.balanceOf(accounts[5])
console.log('Customer balance:', balance.toString())
// Customer balance: 1000000000000000000

// Make a deposit from the customer account into a contract
transfer = await contract.transfer(contract.address, Web3.utils.toWei('1', 'ether'), {from: accounts[5]})
console.log('account[5] has deposited 1 ether into the contract')

// Check contract balance
balance = await contract.balanceOf(contract.address)
console.log('Contract balance:', balance.toString())
// Contract balance: 1000000000000000000

// Confirm delivery(service finished)
contract.confirmDelivery(accounts[5], {from: accounts[1]})
console.log('Service has confirmed product delivery')

// Validate delivery with the same fee value that was passed by the service 
contract.validateDelivery(accounts[5], true, {from: accounts[2]});
console.log('account[2] validated accounts[5] process, waiting for others...')
contract.validateDelivery(accounts[5], true, {from: accounts[3]});
console.log('account[3] validated accounts[5] process, waiting for others...')

// Check contract balance after sending validator reward, service fee and burning the rest
balance = await contract.balanceOf(contract.address)
console.log('Contract balance:', balance.toString())
// Contract balance: 0

// Check service balance after sending service fee
balance = await contract.balanceOf(accounts[1])
console.log('Service balance:', balance.toString())
// Service balance: 333333333333333333

// Check one of 3 validators balance after sending validator reward
balance = await contract.balanceOf(accounts[2])
console.log('Validator balance:', balance.toString())
// Validator balance: 111111111111111111
