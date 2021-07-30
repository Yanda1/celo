var YandaEscrow = artifacts.require('YandaEscrow')

module.exports = function (deployer) {
  var customer='0x1425A2eB611452bD7Df6B80Dd49cc23BA5bB3f45';
  var service='0x926E3b3338D3d1a923cB5Dba3Bbe4f804DbB450A';
  var commision=1;
  deployer.deploy(YandaEscrow, customer, service, commision)
}
