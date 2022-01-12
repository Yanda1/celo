// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract YandaToken is Initializable, ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable {

    using SafeMath for uint256;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    address private _owner;

    enum State { AWAITING_COST, AWAITING_TRANSFER, AWAITING_TERMINATION, AWAITING_VALIDATION, COMPLETED }
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
        uint validationPerc;
        uint commissionPerc;
        uint validatorVersion;
    }
    struct Validator {
        uint requests;
        uint validations;
        bool ready;
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
    event CostRequest(
        address indexed customer,
        address indexed service,
        bytes32 indexed productId,
        string data
    );
    event CostResponse(
        address indexed customer,
        address indexed service,
        bytes32 indexed productId,
        uint cost
    );

    modifier onlyService() {
        require(services[msg.sender].validationPerc > 0, "Only service can call this method");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __ERC20_init("YandaToken", "YND");
        __Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("YandaToken");

        _mint(msg.sender, 1000000000 * 10 ** decimals());
        _owner = msg.sender;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function owner() public view virtual returns(address) {
        return _owner;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
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
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }
    
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if(recipient == address(this)) {
            require(
                processes[msg.sender][depositingProducts[msg.sender]].state == State.AWAITING_TRANSFER,
                "You don't have a deposit awaiting process, please create it first"
            );
            require(
                processes[msg.sender][depositingProducts[msg.sender]].cost == amount,
                "Deposit amount doesn't match with the requested cost"
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

    function _setValidatorsReady(address[] memory vList) internal {
        for(uint i=0; i < vList.length; i++) { 
            validators[vList[i]].ready = true;
        }
    }

    function addService(address service, address[] memory vList, uint vPerc, uint cPerc, uint vVer)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        services[service] = Service({
            validators: vList,
            validationPerc: vPerc,
            commissionPerc: cPerc,
            validatorVersion: vVer
        });
        _setValidatorsReady(vList);
    }

    function setValidators(address[] memory vList) public onlyService {
        services[msg.sender].validators = vList;
        _setValidatorsReady(vList);
    }

    function setValidatorVer(uint vVer) public onlyService {
        services[msg.sender].validatorVersion = vVer;
    }

    function _getProcessCost(address customer, address service, bytes32 productId, string memory data) internal {
        emit CostRequest(customer, service, productId, data);
    }

    function createProcess(address service, bytes32 productId, string memory data) public {
        require(services[service].validationPerc > 0, 'Requested service address not found');
        require(processes[msg.sender][productId].service == address(0), 'Process with specified productId already exist');

        _getProcessCost(msg.sender, service, productId, data);

        processes[msg.sender][productId] = Process({
            state: State.AWAITING_COST,
            cost: 0,
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

    function setProcessCost(address customer, bytes32 productId, uint256 cost) public {
        require(validators[msg.sender].ready == true, "Only validator can call this method");
        require(processes[customer][productId].state == State.AWAITING_COST, "Cost is already set");

        processes[customer][productId].cost = cost;
        processes[customer][productId].state = State.AWAITING_TRANSFER;
        emit CostResponse(customer, processes[customer][productId].service, productId, cost);
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

    function startTermination(address customer, bytes32 productId) public {
        require(
            (services[msg.sender].validationPerc > 0) || (msg.sender == customer),
            "Only service or product customer can call this method"
        );
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
        uint256 score = (validators[validator].validations * 100) / validators[validator].requests;
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

    function validateTermination(address customer, bytes32 productId, bool passed) public {
        require(validators[msg.sender].ready == true, "Only validator can call this method");
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
                uint256 reward_amount = (processes[customer][productId].cost * services[processes[customer][productId].service].validationPerc) / 100;
                uint256 executed_amount = _rewardValidators(services[processes[customer][productId].service], reward_amount);
                // Pay service commission
                uint256 commission_amount = (processes[customer][productId].cost * services[processes[customer][productId].service].commissionPerc) / 100;
                this.transfer(payable(processes[customer][productId].service), commission_amount);
                // Burn remaining funds
                _burn(address(this), processes[customer][productId].cost - executed_amount - commission_amount);
                emit Complete(customer, processes[customer][productId].service, productId, true);
            } else {
                if(processes[customer][productId].failedValidations >= services[processes[customer][productId].service].validators.length / 2) {
                    // Update process state to COMPLETED
                    processes[customer][productId].state = State.COMPLETED;
                    // Reward validators
                    uint256 reward_amount = (processes[customer][productId].cost * services[processes[customer][productId].service].validationPerc) / 100;
                    uint256 executed_amount = _rewardValidators(services[processes[customer][productId].service], reward_amount);
                    // Make refund
                    this.transfer(payable(customer), processes[customer][productId].cost - executed_amount);
                    emit Complete(customer, processes[customer][productId].service, productId, false);
                }
            }
        }
    }

    function claimToken(uint256 amount) public returns (bool) {
        if(this.balanceOf(msg.sender) < 5000000 ether && amount <= 1000 ether) {
            _transfer(owner(), _msgSender(), amount);
            return true;
        } else {
            return false;
        }
    }

}
