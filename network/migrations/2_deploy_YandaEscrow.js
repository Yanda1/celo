var YandaEscrow = artifacts.require('YandaEscrow')

module.exports = function (deployer) {
  var service='SERVICE WALLET ADDRESS';
  deployer.deploy(YandaEscrow, service)
}
