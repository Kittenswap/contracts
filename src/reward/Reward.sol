// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ProtocolTimeLibrary} from "../clAMM/libraries/ProtocolTimeLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVoter} from "../interfaces/IVoter.sol";
import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {IReward} from "../interfaces/IReward.sol";

abstract contract Reward is
    IReward,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* constants */
    uint256 public constant DURATION = ProtocolTimeLibrary.WEEK;
    uint256 public constant PRECISION = 1 ether;
    bytes32 public constant NOTIFY_ROLE = keccak256("NOTIFY_ROLE");

    IVoter public voter;
    IVotingEscrow public veKitten;

    uint256 public periodInit; // first period on initialize
    mapping(uint256 _period => mapping(uint256 _tokenId => uint256))
        public tokenIdVotesInPeriod;
    mapping(uint256 _period => uint256) public totalVotesInPeriod;
    mapping(uint256 _period => mapping(address _reward => uint256))
        public rewardForPeriod;
    mapping(uint256 _period => mapping(uint256 _tokenId => mapping(address _reward => uint256)))
        public tokenIdRewardClaimedInPeriod;
    mapping(uint256 _tokenId => uint256) fullClaimedPeriod;

    EnumerableSet.AddressSet internal rewardTokenList;

    /* action lock */
    mapping(uint256 _blockNumber => mapping(address _user => bool)) userActionLocked; // 1 action per block, eg deposit or withdraw

    /* modifiers */
    modifier actionLock() {
        require(
            userActionLocked[block.number][msg.sender] == false,
            "Action Locked"
        );
        userActionLocked[block.number][msg.sender] = true;
        _;
    }

    modifier onlyVoter() {
        if (msg.sender != address(voter)) revert NotVoter();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function __Reward_init(
        address _voter,
        address _veKitten,
        address _initialOwner
    ) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __Ownable_init(_initialOwner);
        __ReentrancyGuard_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);

        voter = IVoter(_voter);
        veKitten = IVotingEscrow(_veKitten);

        periodInit = getCurrentPeriod();
    }

    /* public functions */
    function getRewardForPeriod(
        uint256 _period,
        uint256 _tokenId,
        address _token
    ) external virtual nonReentrant {
        if (!veKitten.isApprovedOrOwner(msg.sender, _tokenId))
            revert NotApprovedOrOwner();
        if (_period > getCurrentPeriod()) revert FuturePeriodNotClaimable();

        _getReward(_period, _tokenId, _token, msg.sender);
    }

    function getRewardForTokenId(
        uint256 _tokenId
    ) external virtual nonReentrant {
        if (!veKitten.isApprovedOrOwner(msg.sender, _tokenId))
            revert NotApprovedOrOwner();

        _getRewardForTokenId(_tokenId, msg.sender);
    }

    function getRewardForOwner(uint256 _tokenId) external virtual nonReentrant {
        if (msg.sender != address(voter)) revert NotVoter();

        _getRewardForTokenId(_tokenId, veKitten.ownerOf(_tokenId));
    }

    /* view functions */
    function earnedForTokenId(
        uint256 _tokenId
    )
        public
        view
        virtual
        returns (uint256[] memory rewardList, address[] memory tokenList)
    {
        tokenList = rewardTokenList.values();
        uint256 len = rewardTokenList.length();
        rewardList = new uint256[](len);

        for (uint256 i; i < len; ) {
            rewardList[i] = earnedForToken(_tokenId, rewardTokenList.at(i));

            unchecked {
                ++i;
            }
        }
    }

    function earnedForToken(
        uint256 _tokenId,
        address _token
    ) public view virtual returns (uint256 reward) {
        uint256 period = fullClaimedPeriod[_tokenId] > periodInit
            ? fullClaimedPeriod[_tokenId]
            : periodInit;
        uint256 currentPeriod = getCurrentPeriod();
        for (; period <= currentPeriod; ) {
            reward += _earned(period, _tokenId, _token);

            unchecked {
                ++period;
            }
        }
    }

    function earnedForPeriod(
        uint256 _period,
        uint256 _tokenId,
        address _token
    ) public view virtual returns (uint256) {
        return _earned(_period, _tokenId, _token);
    }

    function getCurrentPeriod() public view virtual returns (uint256) {
        return block.timestamp / DURATION;
    }

    function getRewardList() external view virtual returns (address[] memory) {
        return rewardTokenList.values();
    }

    /* only voter functions */
    function _deposit(
        uint256 _amount,
        uint256 _tokenId
    ) external virtual onlyVoter {
        uint256 nextPeriod = getCurrentPeriod() + 1;

        tokenIdVotesInPeriod[nextPeriod][_tokenId] += _amount;
        totalVotesInPeriod[nextPeriod] += _amount;

        emit Deposit(nextPeriod, _amount, _tokenId);
    }

    function _withdraw(
        uint256 _amount,
        uint256 _tokenId
    ) external virtual onlyVoter {
        uint256 nextPeriod = getCurrentPeriod() + 1;

        if (tokenIdVotesInPeriod[nextPeriod][_tokenId] > 0) {
            tokenIdVotesInPeriod[nextPeriod][_tokenId] -= _amount;
            totalVotesInPeriod[nextPeriod] -= _amount;
            emit Withdraw(nextPeriod, _amount, _tokenId);
        }
    }

    function grantNotifyRole(address _account) external virtual;

    /* only notify role functions */
    function notifyRewardAmount(
        address _token,
        uint256 _amount
    ) public virtual nonReentrant onlyRole(NOTIFY_ROLE) {
        uint256 currentPeriod = getCurrentPeriod();
        _addReward(currentPeriod, _token, _amount);

        emit NotifyReward(currentPeriod, msg.sender, _token, _amount);
    }

    function incentivize(
        address _token,
        uint256 _amount
    ) public virtual nonReentrant {
        if (voter.isWhitelisted(_token) == false)
            revert NotWhitelistedRewardToken();

        uint256 currentPeriod = getCurrentPeriod() + 1;
        uint256 amount = _addReward(currentPeriod, _token, _amount);

        emit IncentivizedReward(currentPeriod, msg.sender, _token, amount);
    }

    /* internal functions */
    function _addReward(
        uint256 _period,
        address _token,
        uint256 _amount
    ) internal virtual returns (uint256 amount) {
        rewardTokenList.add(_token);

        IERC20 token = IERC20(_token);
        uint256 tokenBalBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 tokenBalAfter = token.balanceOf(address(this));

        amount = tokenBalAfter - tokenBalBefore;
        rewardForPeriod[_period][_token] += amount;
    }

    function _getReward(
        uint256 _period,
        uint256 _tokenId,
        address _token,
        address _owner
    ) internal virtual;

    function _getRewardForTokenId(
        uint256 _tokenId,
        address _to
    ) internal virtual {
        uint256 len = rewardTokenList.length();
        address[] memory tokenList = rewardTokenList.values();
        uint256 currentPeriod = getCurrentPeriod();
        for (uint256 i; i < len; ) {
            uint256 period = fullClaimedPeriod[_tokenId] > periodInit
                ? fullClaimedPeriod[_tokenId]
                : periodInit;
            for (; period <= currentPeriod; ) {
                _getReward(period, _tokenId, tokenList[i], _to);
                unchecked {
                    ++period;
                }
            }
            unchecked {
                ++i;
            }
        }
        fullClaimedPeriod[_tokenId] = currentPeriod;
    }

    function _earned(
        uint256 _period,
        uint256 _tokenId,
        address _token
    ) internal view virtual returns (uint256 reward) {
        if (totalVotesInPeriod[_period] > 0) {
            reward =
                (rewardForPeriod[_period][_token] *
                    tokenIdVotesInPeriod[_period][_tokenId] *
                    PRECISION) /
                totalVotesInPeriod[_period] /
                PRECISION;

            reward -= tokenIdRewardClaimedInPeriod[_period][_tokenId][_token];
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
