// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.7.0;

contract YandaEscrow {
  enum State { AWAITING_PAYMENT, AWAITING_DELIVERY, AWAITING_VALIDATION, COMPLETE }
  State public currState;
  address payable customer;
  address payable service;
  address payable validator;
  uint public commission = 10;
  uint serviceResult;
  uint public validator_reward;
  uint constant reward_divisor = 10;

  event Deposited(address indexed payee, uint256 weiAmount);

  modifier onlyService() {
    require(msg.sender == service, "Only service can call this method");
    _;
  }

  modifier onlyValidator() {
    require(msg.sender == validator, "Only validator can call this method");
    _;
  }

  constructor(address payable _service) public {
    service = _service;
  }

  receive() external payable {
    require(currState == State.AWAITING_PAYMENT, "Already paid");
    customer = msg.sender;
    currState = State.AWAITING_DELIVERY;
    emit Deposited(msg.sender, msg.value);
  }

  function setCommission(uint _commission) onlyService external {
    commission = _commission;
  }

  function random(uint max) private view returns (uint8) {
    uint[] memory random_data = new uint[](2);
    random_data[0] = block.timestamp;
    random_data[1] = block.difficulty;
    return uint8(uint256(keccak256(abi.encodePacked(random_data))) % max);
  }

  function confirmDelivery(uint _fee, address payable[] calldata _validators) onlyService external {
    require(currState == State.AWAITING_DELIVERY, "Cannot confirm delivery");
    serviceResult = _fee;
    // Random weighted random pick
    validator = _validators[random(_validators.length)];
    currState = State.AWAITING_VALIDATION;
  }

  function validateDelivery(uint _fee) onlyValidator external {
    require(currState == State.AWAITING_VALIDATION, "Cannot validate delivary");
    uint validatorResult = _fee;
    require(serviceResult == validatorResult, "Service and Validator values doesn't match!");

    validator_reward = serviceResult / reward_divisor;

    validator.transfer(validator_reward);
    service.transfer(serviceResult - validator_reward);
    customer.transfer(address(this).balance);

    currState = State.COMPLETE;
  }

  function getState() public view returns (State) {
    return currState;
  }

  function getComission() public view returns (uint) {
    return commission;
  }

  function getValidator() public view returns (address) {
    return validator;
  }

  function getReward() public view returns (uint) {
    return validator_reward;
  }

}
