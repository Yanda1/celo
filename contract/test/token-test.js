const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("YandaToken Test", function () {
  it("Create new service and product, declare actions and terminate", async function () {
    // Deploy YandaToken
    const Token = await ethers.getContractFactory("YandaToken");
    const token = await upgrades.deployProxy(Token);
    await token.deployed();
    // Get all accounts
    const accounts = await ethers.getSigners();
    // Add service from account 1, validator accounts is [2,3,4], validators will get 1/3 and the service 1/3, and the rest will burn
    await token.addService(accounts[1].address, [accounts[2].address, accounts[3].address, accounts[4].address], 33, 33, 9);

    // Transfer 1 YandaToken from token owner to the first validator(accounts[2])
    await token.transfer(accounts[2].address, ethers.utils.parseEther('1'));
    // Transfer 2 YandaToken from token owner to the second validator(accounts[3])
    await token.transfer(accounts[3].address, ethers.utils.parseEther('2'));
    // Transfer 3 YandaToken from token owner to the third validator(accounts[4])
    await token.transfer(accounts[4].address, ethers.utils.parseEther('3'));
    // Transfer 1 YandaToken from token owner to customer account(accounts[5])
    await token.transfer(accounts[5].address, ethers.utils.parseEther('1'));

    // Confirm account #5 balance is equal to 1 YND
    let balance = await token.balanceOf(accounts[5].address);
    expect(ethers.utils.formatEther(balance)).to.equal('1.0');

    // Create process for account #5, cost amount is 1 YandaToken, product id: 123 and data is {"a": 1, "b": 2, "c": 3}
    await token.connect(accounts[5]).createProcess(accounts[1].address, ethers.utils.id('123'), '{"a": 1, "b": 2, "c": 3}');

    // Set process cost by validator account
    await token.connect(accounts[2]).setProcessCost(accounts[5].address, ethers.utils.id('123'), ethers.utils.parseEther('1'));

    // Make smart contract deposit from account #5
    await token.connect(accounts[5]).transfer(token.address, ethers.utils.parseEther('1'));

    // Check contract balance
    balance = await token.balanceOf(token.address);
    expect(ethers.utils.formatEther(balance)).to.equal('1.0');

    // Declare few service produced actions
    await token.connect(accounts[1]).declareAction(accounts[5].address, ethers.utils.id('123'), 'First order data');
    await token.connect(accounts[1]).declareAction(accounts[5].address, ethers.utils.id('123'), 'Second order data');

    // Customer driven termination process starting for the productId '123'
    await token.connect(accounts[5]).startTermination(accounts[5].address, ethers.utils.id('123'));

    // Validator #1 validate termination process for the client accounts[5] with productId "123"
    await token.connect(accounts[2]).validateTermination(accounts[5].address, ethers.utils.id('123'), true);
    // Validator #3 validate termination process for the client accounts[5] with productId "123"
    await token.connect(accounts[4]).validateTermination(accounts[5].address, ethers.utils.id('123'), true);
    // Validator #2 validate termination process for the client accounts[5] with productId "123"
    await token.connect(accounts[3]).validateTermination(accounts[5].address, ethers.utils.id('123'), true);

    // Check contract balance after sending validator reward, service fee and burning the rest, it should be 0
    balance = await token.balanceOf(token.address);
    expect(ethers.utils.formatEther(balance)).to.equal('0.0');

    // Check service balance after sending service fee
    balance = await token.balanceOf(accounts[1].address)
    expect(ethers.utils.formatEther(balance)).to.equal('0.33');

    // Check validator #1 balance after receiving validator reward
    balance = await token.balanceOf(accounts[2].address)
    expect(ethers.utils.formatEther(balance)).to.equal('1.055');

    // Check validator #3 balance after receiving validator reward
    balance = await token.balanceOf(accounts[4].address)
    expect(ethers.utils.formatEther(balance)).to.equal('3.165');

    // Check validator #2 balance after not receiving validator reward
    balance = await token.balanceOf(accounts[3].address)
    expect(ethers.utils.formatEther(balance)).to.equal('2.0');

    // Check token total supply after burning 34% of the product cost
    let supply = await token.totalSupply()
    expect(ethers.utils.formatEther(supply)).to.equal('999999999.55');
  });

});
