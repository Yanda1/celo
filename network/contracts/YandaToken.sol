// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";


contract YandaToken is ERC20, Pausable, Ownable, ERC20Permit, ERC20Votes {
    enum State { AWAITING_TRANSFER, AWAITING_TERMINATION, AWAITING_VALIDATION }
    struct Process {
        State state;
        uint cost;
        address service;
        string productId;
        string productData;
        uint validations;
        uint failedValidations;
    }
    struct Service {
        address[] validators;
        uint validationShare;
        uint commissionShare;
    }
    mapping(address => Process) public processes;
    mapping(address => Service) public services;
    mapping(address => bool) public validators;

    event Deposit(
        address indexed customer,
        address indexed service,
        string indexed productId,
        uint256 weiAmount
    );
    event Action(
        address indexed customer,
        address indexed service,
        string indexed productId,
        string data
    );
    event Terminate(
        address indexed customer,
        address indexed service,
        string productId
    );
    event Complete(
        address indexed customer,
        address indexed service, 
        string productId,
        bool success
    );

    modifier onlyService() {
        require(services[msg.sender].validationShare > 0, "Only service can call this method");
        _;
    }

    modifier onlyValidator() {
        require(validators[msg.sender] == true, "Only validator can call this method");
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
                processes[msg.sender].state == State.AWAITING_TRANSFER,
                "You have another active process, please finish it first"
            );

            _transfer(_msgSender(), recipient, amount);
            processes[msg.sender].state = State.AWAITING_TERMINATION;

            emit Deposit(
                _msgSender(),
                processes[msg.sender].service,
                processes[msg.sender].productId,
                amount
            );
        } else {
            _transfer(_msgSender(), recipient, amount);
        }
        return true;
    }

    function _updateValidatorsMapping(address[] calldata new_validators) internal {
        for(uint i=0; i < new_validators.length; i++) {
            if(!validators[new_validators[i]]) {
                validators[new_validators[i]] = true;
            }
        }
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
        _updateValidatorsMapping(vList);
    }

    function setValidators(address[] calldata vList) public onlyService {
        services[msg.sender].validators = vList;
        _updateValidatorsMapping(vList);
    }

    function createProcess(address service, uint256 amount, string calldata productId, string calldata data)
        public returns(bool)
    {
        if(services[service].validationShare > 0) {
            processes[msg.sender] = Process({
                state: State.AWAITING_TRANSFER,
                cost: amount,
                service: service,
                productId: productId,
                productData: data,
                validations: 0,
                failedValidations: 0
            });
            return true;
        } else {
            return false;
        }
    }

    function declareAction(address customer, string calldata productId, string calldata data)
        public onlyService
    {
        emit Action(customer, msg.sender, productId, data);
    }

    function startTermination(address customer) public onlyService {
        require(processes[customer].state == State.AWAITING_TERMINATION, "Cannot start termination");
        processes[customer].state = State.AWAITING_VALIDATION;
        emit Terminate(customer, msg.sender, processes[customer].productId);
    }

    function _rewardValidators(Service memory service, uint256 amount) internal returns(uint256) {
        uint256 rewards_sum = 0;
        uint256 reward = amount / service.validators.length;

        for(uint i=0; i < service.validators.length; i++) {
            this.transfer(payable(service.validators[i]), reward);
            rewards_sum += reward;
        }
        return rewards_sum;
    }

    function validateTermination(address customer, bool passed) public onlyValidator {
        require(processes[customer].state == State.AWAITING_VALIDATION, "Cannot validate delivary");
        
        if(passed) {
            processes[customer].validations += 1;
        } else {
            processes[customer].failedValidations += 1;
        }

        if(processes[customer].validations > services[processes[customer].service].validators.length / 2) {
            // Reward validators
            uint256 reward_amount = processes[customer].cost / services[processes[customer].service].validationShare;
            uint256 executed_amount = _rewardValidators(services[processes[customer].service], reward_amount);
            // Pay service commission
            uint256 commission_amount = processes[customer].cost / services[processes[customer].service].commissionShare;
            this.transfer(payable(processes[customer].service), commission_amount);
            // Burn remaining funds
            _burn(address(this), processes[customer].cost - executed_amount - commission_amount);
            emit Complete(customer, processes[customer].service, processes[customer].productId, true);
            // Delete completed process
            delete processes[customer];
        } else {
            if(processes[customer].failedValidations >= services[processes[customer].service].validators.length / 2) {
                // Reward validators
                uint256 reward_amount = processes[customer].cost / services[processes[customer].service].validationShare;
                uint256 executed_amount = _rewardValidators(services[processes[customer].service], reward_amount);
                // Make refund
                this.transfer(payable(customer), processes[customer].cost - executed_amount);
                emit Complete(customer, processes[customer].service, processes[customer].productId, false);
                // Delete completed process
                delete processes[customer];
            }
        }
    }

}
