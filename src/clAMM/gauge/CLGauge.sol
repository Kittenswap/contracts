// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../interfaces/IBribe.sol";
import "../../interfaces/IERC20.sol";
import "./interfaces/ICLGauge.sol";
import {IVoter} from "../../interfaces/IVoter.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";

import {INonfungiblePositionManager} from "../periphery/interfaces/INonfungiblePositionManager.flatten.sol";

import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {ICLPool} from "../core/interfaces/ICLPool.sol";

import {FixedPoint128} from "../core/libraries/FixedPoint128.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC721HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library ProtocolTimeLibrary {
    uint256 internal constant WEEK = 7 days;

    /// @dev Returns start of epoch based on current timestamp
    function epochStart(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % WEEK);
    }

    /// @dev Returns start of next epoch / end of current epoch
    function epochNext(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % WEEK) + WEEK;
    }

    /// @dev Returns start of voting window
    function epochVoteStart(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % WEEK) + 1 hours;
    }

    /// @dev Returns end of voting window / beginning of unrestricted voting window
    function epochVoteEnd(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % WEEK) + WEEK - 1 hours;
    }
}

/* 
Changes to original Gauge to support CL:
- each CL NFP tokenId will replace "msg.sender" from the mappings
- nap CL NFP tokenId to msg.sender for deposit and withdrawals
- treat "liquidity" as "token" in "rewardPerTokenStored"
- treat CL NFP tokenId as "user" in "userRewardPerTokenStored"
 */

// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
contract CLGauge is
    ICLGauge,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ERC721HolderUpgradeable
{
    using EnumerableSet for EnumerableSet.UintSet;

    INonfungiblePositionManager public nfp;
    address public token0;
    address public token1;
    int24 public tickSpacing;

    mapping(address => EnumerableSet.UintSet) internal userStakedNFPs;

    ICLPool public pool;

    mapping(uint256 nfpTokenId => uint256) public rewardGrowthInside;
    mapping(uint256 nfpTokenId => uint256) public lastUpdateTime;

    mapping(uint256 nfpTokenId => uint256) public rewards;

    address public kitten;

    /* events */
    event Deposit(
        address indexed from,
        uint256 nfpTokenId,
        uint256 tokenId,
        uint256 liquidityStaked
    );
    event Withdraw(
        address indexed from,
        uint256 nfpTokenId,
        uint tokenId,
        uint liquidityUnstaked
    );

    /* errors */
    error CLGauge__InvalidTokenId();

    address public _ve; // the ve token used for gauges
    address public internal_bribe;
    address public voter;

    uint public derivedSupply;
    mapping(address => uint) public derivedBalances;

    bool public isForPair;

    uint internal constant PRECISION = 10 ** 18;
    uint internal constant MAX_REWARD_TOKENS = 16;

    // default snx staking contract implementation
    uint public rewardRate;
    uint public periodFinish;

    mapping(address => uint) public tokenIds;

    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    mapping(address => bool) public isReward;

    uint public fees0;
    uint public fees1;

    event NotifyReward(address indexed from, uint amount);
    event ClaimFees(address indexed from, uint claimed0, uint claimed1);
    event ClaimRewards(address indexed from, uint amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _pool,
        address _internal_bribe,
        address _kitten,
        address __ve,
        address _voter,
        address _nfp,
        bool _forPair
    ) external initializer {
        pool = ICLPool(_pool);
        internal_bribe = _internal_bribe;
        kitten = _kitten;
        _ve = __ve;
        voter = _voter;

        nfp = INonfungiblePositionManager(_nfp);
        token0 = pool.token0();
        token1 = pool.token1();
        tickSpacing = pool.tickSpacing();

        isForPair = _forPair;
        _unlocked = 1;

        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ERC721Holder_init();
    }

    // simple re-entrancy check
    uint internal _unlocked;
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    mapping(uint _blockNumber => mapping(address _user => bool)) userBlockLocked; // 1 action per block, eg deposit or withdraw

    modifier actionLock() {
        require(
            userBlockLocked[block.number][msg.sender] == false,
            "Action Locked"
        );
        userBlockLocked[block.number][msg.sender] = true;
        _;
    }

    function claimFees() external lock returns (uint claimed0, uint claimed1) {
        return _claimFees();
    }

    function _claimFees() internal returns (uint claimed0, uint claimed1) {
        if (!isForPair) return (0, 0);

        uint256 token0BalBefore = IERC20(token0).balanceOf(address(this));
        uint256 token1BalBefore = IERC20(token1).balanceOf(address(this));
        (claimed0, claimed1) = pool.collectFees();
        uint256 token0BalAfter = IERC20(token0).balanceOf(address(this));
        uint256 token1BalAfter = IERC20(token1).balanceOf(address(this));

        if (claimed0 > 0 || claimed1 > 0) {
            uint _fees0 = fees0 + claimed0;
            uint _fees1 = fees1 + claimed1;

            if (token0BalAfter - token0BalBefore == claimed0) {
                if (
                    _fees0 > IBribe(internal_bribe).left(token0) &&
                    _fees0 / ProtocolTimeLibrary.WEEK > 0
                ) {
                    fees0 = 0;
                    _safeApprove(token0, internal_bribe, _fees0);
                    IBribe(internal_bribe).notifyRewardAmount(token0, _fees0);
                } else {
                    fees0 = _fees0;
                }
                emit ClaimFees(msg.sender, claimed0, 0);
            }
            if (token1BalAfter - token1BalBefore == claimed1) {
                if (
                    _fees1 > IBribe(internal_bribe).left(token1) &&
                    _fees1 / ProtocolTimeLibrary.WEEK > 0
                ) {
                    fees1 = 0;
                    _safeApprove(token1, internal_bribe, _fees1);
                    IBribe(internal_bribe).notifyRewardAmount(token1, _fees1);
                } else {
                    fees1 = _fees1;
                }
                emit ClaimFees(msg.sender, 0, claimed1);
            }
        }
    }

    function getReward(
        address account,
        address[] calldata tokens
    ) external lock {
        address msgSender = msg.sender;
        require(
            msgSender == account || msgSender == voter,
            "Not Owner or Voter"
        );

        uint256[] memory nfpTokenIdList = userStakedNFPs[account].values();
        uint256 len = nfpTokenIdList.length;

        for (uint256 i; i < len; ) {
            _getReward(nfpTokenIdList[i], msgSender);

            unchecked {
                ++i;
            }
        }
    }

    function getReward(uint256 nfpTokenId) external lock {
        address msgSender = msg.sender;
        require(userStakedNFPs[msgSender].contains(nfpTokenId), "Not Owner");

        _getReward(nfpTokenId, msgSender);
    }

    function _getReward(uint256 nfpTokenId, address owner) internal {
        (, , , , , int24 _tickLower, int24 _tickUpper, , , , , ) = nfp
            .positions(nfpTokenId);

        _updateRewardForNfp(nfpTokenId, _tickLower, _tickUpper);

        uint256 reward = rewards[nfpTokenId];

        if (reward > 0) {
            delete rewards[nfpTokenId];
            _safeApprove(kitten, address(this), reward);
            _safeTransferFrom(kitten, address(this), owner, reward);
            emit ClaimRewards(owner, reward);
        }
    }

    function _updateRewardForNfp(
        uint256 nfpTokenId,
        int24 _tickLower,
        int24 _tickUpper
    ) internal {
        if (lastUpdateTime[nfpTokenId] == block.timestamp) return;
        pool.updateRewardsGrowthGlobal();
        lastUpdateTime[nfpTokenId] = block.timestamp;
        rewards[nfpTokenId] += earned(nfpTokenId);
        rewardGrowthInside[nfpTokenId] = pool.getRewardGrowthInside(
            _tickLower,
            _tickUpper,
            0
        );
    }

    function earned(uint256 nfpTokenId) public view returns (uint) {
        uint256 timeDelta = block.timestamp - pool.lastUpdated();

        uint256 rewardGrowthGlobalX128 = pool.rewardGrowthGlobalX128();
        uint256 rewardReserve = pool.rewardReserve();

        if (timeDelta != 0 && rewardReserve > 0 && pool.stakedLiquidity() > 0) {
            uint256 reward = rewardRate * timeDelta;
            if (reward > rewardReserve) reward = rewardReserve;

            rewardGrowthGlobalX128 += Math.mulDiv(
                reward,
                FixedPoint128.Q128,
                pool.stakedLiquidity()
            );
        }

        (
            ,
            ,
            ,
            ,
            ,
            int24 _tickLower,
            int24 _tickUpper,
            uint128 _liquidity,
            ,
            ,
            ,

        ) = nfp.positions(nfpTokenId);

        uint256 rewardGrowthInsideInitial = rewardGrowthInside[nfpTokenId];
        uint256 rewardGrowthInsideCurrent = pool.getRewardGrowthInside(
            _tickLower,
            _tickUpper,
            rewardGrowthGlobalX128
        );

        uint256 rewardGrowthInsideDelta = rewardGrowthInsideCurrent -
            rewardGrowthInsideInitial;

        return
            Math.mulDiv(
                rewardGrowthInsideDelta,
                _liquidity,
                FixedPoint128.Q128
            );
    }

    function getUserStakedNFPs(
        address account
    ) external view returns (uint256[] memory nfpTokenIdList) {
        return userStakedNFPs[account].values();
    }

    function getUserStakedNFPsLength(
        address account
    ) external view returns (uint256) {
        return userStakedNFPs[account].length();
    }

    // deposit NFP tokenId
    function deposit(
        uint256 nfpTokenId,
        uint256 tokenId
    ) public lock actionLock {
        (
            ,
            ,
            address _token0,
            address _token1,
            int24 _tickSpacing,
            int24 _tickLower,
            int24 _tickUpper,
            uint128 _liquidity,
            ,
            ,
            ,

        ) = nfp.positions(nfpTokenId);

        // collect for nfpTokenId prior to deposit into gauge
        if (
            _token0 != token0 ||
            _token1 != token1 ||
            _tickSpacing != tickSpacing
        ) revert CLGauge__InvalidTokenId();

        nfp.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: nfpTokenId,
                recipient: msg.sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // deposit nfp in gauge
        nfp.safeTransferFrom(msg.sender, address(this), nfpTokenId);
        userStakedNFPs[msg.sender].add(nfpTokenId);

        // stake nfp liquidity in pool
        pool.stake(
            SafeCast.toInt128(SafeCast.toInt256(uint256(_liquidity))),
            _tickLower,
            _tickUpper,
            true
        );

        // set initial reward growth as reference for calc rewards over time
        uint256 rewardGrowth = pool.getRewardGrowthInside(
            _tickLower,
            _tickUpper,
            0
        );
        rewardGrowthInside[nfpTokenId] = rewardGrowth;
        lastUpdateTime[nfpTokenId] = block.timestamp;

        // attach ve
        if (tokenId > 0) {
            require(IVotingEscrow(_ve).ownerOf(tokenId) == msg.sender);
            if (tokenIds[msg.sender] == 0) {
                tokenIds[msg.sender] = tokenId;
                IVoter(voter).attachTokenToGauge(tokenId, msg.sender);
            }
            require(tokenIds[msg.sender] == tokenId);
        } else {
            tokenId = tokenIds[msg.sender];
        }

        IVoter(voter).emitDeposit(tokenId, msg.sender, _liquidity);
        emit Deposit(msg.sender, nfpTokenId, tokenId, _liquidity);
    }

    function withdraw(uint nfpTokenId) public lock actionLock {
        address msgSender = msg.sender;
        require(userStakedNFPs[msgSender].contains(nfpTokenId), "Not Owner");

        nfp.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: nfpTokenId,
                recipient: msgSender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        (
            ,
            ,
            ,
            ,
            ,
            int24 _tickLower,
            int24 _tickUpper,
            uint128 _liquidity,
            ,
            ,
            ,

        ) = nfp.positions(nfpTokenId);

        _getReward(nfpTokenId, msgSender);

        if (_liquidity != 0)
            pool.stake(
                -SafeCast.toInt128(SafeCast.toInt256(uint256(_liquidity))),
                _tickLower,
                _tickUpper,
                true
            );

        userStakedNFPs[msg.sender].remove(nfpTokenId);
        nfp.safeTransferFrom(address(this), msg.sender, nfpTokenId);

        uint tokenId = tokenIds[msg.sender];
        if (tokenId > 0) {
            require(tokenId == tokenIds[msg.sender]);
            tokenIds[msg.sender] = 0;
            IVoter(voter).detachTokenFromGauge(tokenId, msg.sender);
        } else {
            tokenId = tokenIds[msg.sender];
        }

        emit Withdraw(msg.sender, nfpTokenId, tokenId, _liquidity);
    }

    function left(address token) external view returns (uint) {
        if (block.timestamp >= periodFinish) return 0;
        uint _remaining = periodFinish - block.timestamp;
        return _remaining * rewardRate;
    }

    function notifyRewardAmount(address token, uint amount) external lock {
        require(amount > 0);
        require(token == kitten);

        _claimFees();
        pool.updateRewardsGrowthGlobal();

        address msgSender = msg.sender;
        uint timestamp = block.timestamp;
        uint epochDurationLeft = ProtocolTimeLibrary.epochNext(timestamp) -
            timestamp;

        _safeTransferFrom(kitten, msgSender, address(this), amount);
        amount = amount + pool.rollover();

        uint256 nextPeriodFinish = timestamp + epochDurationLeft;

        if (block.timestamp >= periodFinish) {
            rewardRate = amount / epochDurationLeft;
            pool.syncReward({
                rewardRate: rewardRate,
                rewardReserve: amount,
                periodFinish: nextPeriodFinish
            });
        } else {
            uint256 newAmount = amount + epochDurationLeft * rewardRate;
            rewardRate = newAmount / epochDurationLeft;
            pool.syncReward({
                rewardRate: rewardRate,
                rewardReserve: newAmount,
                periodFinish: nextPeriodFinish
            });
        }

        require(rewardRate > 0);
        uint balance = IERC20(kitten).balanceOf(address(this));
        require(
            rewardRate <= balance / epochDurationLeft,
            "Provided reward too high"
        );
        periodFinish = nextPeriodFinish;

        emit NotifyReward(msgSender, amount);
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeApprove(
        address token,
        address spender,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function transferERC20(address token) external onlyOwner {
        IERC20(token).transfer(
            msg.sender,
            IERC20(token).balanceOf(address(this))
        );
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
