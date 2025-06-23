// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ProtocolTimeLibrary} from "../clAMM/libraries/ProtocolTimeLibrary.sol";
import {IGauge} from "../interfaces/IGauge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IReward} from "../interfaces/IReward.sol";
import {IPair} from "../interfaces/IPair.sol";

/* Gauge */
// - distribute rewards over 1 week period
// - only emission KITTEN token can be notified to the gauge
// - only voter and authorized can notify rewards
// - users deposit and withdraw lp tokens to earn emissions over the period

contract Gauge is
    IGauge,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /* constants */
    uint256 public constant DURATION = ProtocolTimeLibrary.WEEK;
    uint256 public constant PRECISION = 1 ether;
    bytes32 public constant AUTHORIZED_ROLE = keccak256("AUTHORIZED_ROLE");

    IERC20 public lpToken; // staking token
    IERC20 public kitten; // rewards token

    IVoter public voter;
    IReward public votingReward;

    // Timestamp of when the rewards finish
    uint256 public finishAt;
    // Minimum of last updated time and reward finish time
    uint256 public updatedAt;
    // Reward to be paid out per second in PRECISION units
    uint256 public rewardRate;
    // Sum of (reward rate * dt / total supply) in PRECISION units
    uint256 public rewardPerTokenStored;
    // User address => rewardPerTokenStored
    mapping(address => uint256) public userRewardPerTokenPaid;
    // User address => rewards to be claimed
    mapping(address => uint256) public rewards;
    // Total staked
    uint256 public totalSupply;
    // User address => staked amount
    mapping(address => uint256) public balanceOf;

    /* action lock */
    mapping(uint256 _blockNumber => mapping(address _user => bool)) userActionLocked; // 1 action per block, eg deposit or withdraw

    /* modifiers */
    modifier actionLock() {
        if (userActionLocked[block.number][msg.sender]) revert ActionLocked();
        userActionLocked[block.number][msg.sender] = true;
        _;
    }

    modifier onlyVoterOrAuthorized() {
        if (
            msg.sender != address(voter) &&
            hasRole(AUTHORIZED_ROLE, msg.sender) == false
        ) {
            revert NotVoterOrAuthorized();
        }
        _;
    }

    modifier updateReward(address _account) {
        rewardPerTokenStored = rewardPerToken();
        updatedAt = lastTimeRewardApplicable();

        if (_account != address(0)) {
            rewards[_account] = earned(_account);
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _lpToken,
        address _kitten,
        address _voter,
        address _votingReward,
        address _initialOwner
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __Ownable_init(_initialOwner);
        __AccessControl_init();
        __ReentrancyGuard_init();

        lpToken = IERC20(_lpToken);
        kitten = IERC20(_kitten);

        voter = IVoter(_voter);
        votingReward = IReward(_votingReward);

        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        _grantRole(AUTHORIZED_ROLE, _initialOwner);
    }

    /* public functions */
    function deposit(
        uint256 _amount
    ) external nonReentrant actionLock updateReward(msg.sender) {
        if (_amount == 0) revert ZeroAmount();
        lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;
    }

    function withdraw(
        uint256 _amount
    ) external nonReentrant actionLock updateReward(msg.sender) {
        if (_amount == 0) revert ZeroAmount();
        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        lpToken.safeTransfer(msg.sender, _amount);
    }

    function getReward(address _account) external updateReward(_account) {
        if (msg.sender != _account && msg.sender != address(voter))
            revert NotOwnerOrVoter();

        uint256 reward = rewards[_account];
        if (reward > 0) {
            rewards[_account] = 0;
            kitten.transfer(_account, reward);
        }
    }

    /* view functions */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return finishAt < block.timestamp ? finishAt : block.timestamp; // min
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (rewardRate * (lastTimeRewardApplicable() - updatedAt)) /
            totalSupply;
    }

    function earned(address _account) public view returns (uint256) {
        uint256 rewardPerTokenDelta = rewardPerToken() -
            userRewardPerTokenPaid[_account];

        return
            rewards[_account] +
            ((balanceOf[_account] * rewardPerTokenDelta) / PRECISION);
    }

    // rewards remaining
    function left() public view returns (uint256) {
        if (block.timestamp < finishAt) {
            return ((finishAt - block.timestamp) * rewardRate) / PRECISION;
        }

        return 0;
    }

    function notifyRewardAmount(
        uint256 _amount
    ) external onlyVoterOrAuthorized updateReward(address(0)) {
        _claimFees();

        kitten.safeTransferFrom(msg.sender, address(this), _amount);

        if (block.timestamp >= finishAt) {
            rewardRate = (_amount * PRECISION) / DURATION;
        } else {
            uint256 remainingRewards = (finishAt - block.timestamp) *
                rewardRate;
            if (_amount * PRECISION <= remainingRewards)
                revert NotifyLessThanEqualToLeft();
            rewardRate = ((_amount * PRECISION) + remainingRewards) / DURATION;
        }
        if (rewardRate == 0) revert ZeroRewardRate();
        if (
            (rewardRate * DURATION) / PRECISION >
            kitten.balanceOf(address(this))
        ) revert RewardRateExceedBalance();

        finishAt = block.timestamp + DURATION;
        updatedAt = block.timestamp;
    }

    /* internal functions */
    function _claimFees()
        internal
        returns (uint256 claimed0, uint256 claimed1)
    {
        (claimed0, claimed1) = IPair(address(lpToken)).claimFees();
        (address _token0, address _token1) = IPair(address(lpToken)).tokens();
        if (claimed0 > 0) {
            IERC20(_token0).approve(address(votingReward), claimed0);
            votingReward.notifyRewardAmount(_token0, claimed0);
        }
        if (claimed1 > 0) {
            IERC20(_token1).approve(address(votingReward), claimed1);
            votingReward.notifyRewardAmount(_token1, claimed1);
        }

        emit ClaimAndNotifyFees(msg.sender, claimed0, claimed1);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
