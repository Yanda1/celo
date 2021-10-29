// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";


contract YandaToken is ERC20, Pausable, Ownable, ERC20Permit, ERC20Votes {
    enum State { AWAITING_TRANSFER, AWAITING_TERMINATION, AWAITING_VALIDATION, COMPLETED }
    struct Process {
        State state;
        uint cost;
        address service;
        bytes32 productId;
        string productData;
        uint validations;
        uint failedValidations;
    }
    struct Service {
        address[] validators;
        uint validationShare;
        uint commissionShare;
    }
    struct Validator {
        uint requests;
        uint validations;
    }
    mapping(address => mapping(bytes32 => Process)) public processes;
    mapping(address => bytes32) public depositingProducts;
    mapping(address => Service) public services;
    mapping(address => Validator) public validators;

    event Deposit(
        address indexed customer,
        address indexed service,
        bytes32 indexed productId,
        uint256 weiAmount
    );
    event Action(
        address indexed customer,
        address indexed service,
        bytes32 indexed productId,
        string data
    );
    event Terminate(
        address indexed customer,
        address indexed service,
        bytes32 indexed productId
    );
    event Complete(
        address indexed customer,
        address indexed service, 
        bytes32 indexed productId,
        bool success
    );

    modifier onlyService() {
        require(services[msg.sender].validationShare > 0, "Only service can call this method");
        _;
    }

    modifier onlyValidator() {
        require(validators[msg.sender].requests > 0, "Only validator can call this method");
        _;
    }

    constructor() ERC20("YandaToken", "YND") ERC20Permit("YandaToken") {
        _mint(msg.sender, 100000 * 10 ** decimals());
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
    
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if(recipient == address(this)) {
            require(
                processes[msg.sender][depositingProducts[msg.sender]].state == State.AWAITING_TRANSFER,
                "You don't have a deposit awaiting process, please create it first"
            );

            _transfer(_msgSender(), recipient, amount);
            processes[msg.sender][depositingProducts[msg.sender]].state = State.AWAITING_TERMINATION;

            emit Deposit(
                _msgSender(),
                processes[msg.sender][depositingProducts[msg.sender]].service,
                processes[msg.sender][depositingProducts[msg.sender]].productId,
                amount
            );
        } else {
            _transfer(_msgSender(), recipient, amount);
        }
        return true;
    }

    function addService(address service, address[] calldata vList, uint vShare, uint cShare)
        public
        onlyOwner
    {
        services[service] = Service({
            validators: vList,
            validationShare: vShare,
            commissionShare: cShare
        });
    }

    function setValidators(address[] calldata vList) public onlyService {
        services[msg.sender].validators = vList;
    }

    function createProcess(address service, uint256 amount, bytes32 productId, string calldata data) public {
        require(services[service].validationShare > 0, 'Requested service address not found');
        require(processes[msg.sender][productId].service == address(0), 'Process with specified productId already exist');

        processes[msg.sender][productId] = Process({
            state: State.AWAITING_TRANSFER,
            cost: amount,
            service: service,
            productId: productId,
            productData: data,
            validations: 0,
            failedValidations: 0
        });
        if(depositingProducts[msg.sender].length > 0) {
            // Delete previous product if still waits for a deposit
            if(processes[msg.sender][depositingProducts[msg.sender]].state == State.AWAITING_TRANSFER) {
                delete processes[msg.sender][depositingProducts[msg.sender]];
            }
        }
        depositingProducts[msg.sender] = productId;
    }

    function declareAction(address customer, bytes32 productId, string calldata data)
        public onlyService
    {
        emit Action(customer, msg.sender, productId, data);
    }

    function _updateValidatorsScore(Service memory service) internal {
        for(uint i=0; i < service.validators.length; i++) { 
            validators[service.validators[i]].requests += 1;
        }
    }

    function startTermination(address customer, bytes32 productId) public onlyService {
        require(processes[customer][productId].state == State.AWAITING_TERMINATION, "Cannot start termination");
        processes[customer][productId].state = State.AWAITING_VALIDATION;
        // Update validators requests score
        _updateValidatorsScore(services[processes[customer][productId].service]);
        // Emit Terminate event to trigger validators
        emit Terminate(customer, msg.sender, productId);
    }

    function _validatorsHolding(Service memory service) view internal returns(uint256) {
        uint256 result = 0;
        for(uint i=0; i < service.validators.length; i++) { 
            result += this.balanceOf(service.validators[i]);
        }
        return result;
    }

    function _scoredReward(address validator, uint256 reward) view internal returns(uint256) {
        uint256 score = (validators[validator].validations * 100) /  validators[validator].requests;
        return (reward * score) / 100;
    }

    function _rewardValidators(Service memory service, uint256 amount) internal returns(uint256) {
        uint256 rewards_sum = 0;
        // Sum of validators YND token balances
        uint256 holdings = _validatorsHolding(service);

        for(uint i=0; i < service.validators.length; i++) {
            uint256 validator_balance = this.balanceOf(service.validators[i]);
            if(validator_balance > 0) {
                uint256 reward = amount / (holdings / validator_balance);
                // Reward after scoring filter
                uint256 scored_reward = _scoredReward(service.validators[i], reward);
                if(scored_reward > 0) {
                    this.transfer(payable(service.validators[i]), scored_reward);
                    rewards_sum += scored_reward;
                }
            }
        }
        return rewards_sum;
    }

    function validateTermination(address customer, bytes32 productId, bool passed) public onlyValidator {
        require(processes[customer][productId].state >= State.AWAITING_VALIDATION, "Cannot validate delivary");
        
        if(passed) {
            processes[customer][productId].validations += 1;
        } else {
            processes[customer][productId].failedValidations += 1;
        }
        // Update validator score
        validators[msg.sender].validations += 1;

        if(processes[customer][productId].state == State.AWAITING_VALIDATION) {
            if(processes[customer][productId].validations > services[processes[customer][productId].service].validators.length / 2) {
                // Update process state to COMPLETED
                processes[customer][productId].state = State.COMPLETED;
                // Reward validators
                uint256 reward_amount = processes[customer][productId].cost / services[processes[customer][productId].service].validationShare;
                uint256 executed_amount = _rewardValidators(services[processes[customer][productId].service], reward_amount);
                // Pay service commission
                uint256 commission_amount = processes[customer][productId].cost / services[processes[customer][productId].service].commissionShare;
                this.transfer(payable(processes[customer][productId].service), commission_amount);
                // Burn remaining funds
                _burn(address(this), processes[customer][productId].cost - executed_amount - commission_amount);
                emit Complete(customer, processes[customer][productId].service, productId, true);
            } else {
                if(processes[customer][productId].failedValidations >= services[processes[customer][productId].service].validators.length / 2) {
                    // Update process state to COMPLETED
                    processes[customer][productId].state = State.COMPLETED;
                    // Reward validators
                    uint256 reward_amount = processes[customer][productId].cost / services[processes[customer][productId].service].validationShare;
                    uint256 executed_amount = _rewardValidators(services[processes[customer][productId].service], reward_amount);
                    // Make refund
                    this.transfer(payable(customer), processes[customer][productId].cost - executed_amount);
                    emit Complete(customer, processes[customer][productId].service, productId, false);
                }
            }
        }
    }

}
