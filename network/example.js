// Get deployed contract
let contract = await YandaEscrow.deployed()

// Check contract state
contract.getState()
// ... words: [ 0, <1 empty item> ], ...

// Check contract balance
let balance = await web3.eth.getBalance(contract.address)
balance
// 0

// Get all accounts
let accounts = await web3.eth.getAccounts()

// Make a deposit from the customer account into contract
let deposit = await web3.eth.sendTransaction({from: accounts[0], to: contract.address, value: 30})

// Check contract balance
balance = await web3.eth.getBalance(contract.address)
balance
// 30

// Check contract state after deposit
contract.getState()
// ... words: [ 1, <1 empty item> ], ...

// Confirm delivery(service finished)
contract.confirmDelivery(20, accounts.slice(2))

// Check contract state after delivery
contract.getState()
// ... words: [ 2, <1 empty item> ], ...

// Check that validator was selected from delivery sugested validators list
contract.getValidator()
// selected validator address

// Validate delivery with the same fee value that was passed by the service 
contract.validateDelivery(20)

// Check contract balance after sending validator reward, service fee and customer refund
balance = await web3.eth.getBalance(contract.address)
balance
// 0

// Check contract state after validation
contract.getState()
// ... words: [ 3, <1 empty item> ], ...
