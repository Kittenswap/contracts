// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC721HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPoint128} from "../core/libraries/FixedPoint128.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ICLGauge} from "./interfaces/ICLGauge.sol";
import {IVoter} from "../../interfaces/IVoter.sol";
import {IVotingEscrow} from "../../interfaces/IVotingEscrow.sol";
import {INonfungiblePositionManager} from "../periphery/interfaces/INonfungiblePositionManager.flatten.sol";
import {ICLPool} from "../core/interfaces/ICLPool.sol";
import {ProtocolTimeLibrary} from "../libraries/ProtocolTimeLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotingReward} from "../../interfaces/IVotingReward.sol";

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
    ERC721HolderUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    uint256 internal constant PRECISION = 10 ** 18;

    INonfungiblePositionManager public nfp;
    IERC20 public kitten;
    ICLPool public pool;
    IERC20 public token0;
    IERC20 public token1;
    int24 public tickSpacing;

    address public voter;
    IVotingReward public votingReward;

    mapping(address => EnumerableSet.UintSet) internal userStakedNFPs;
    mapping(uint256 nfpTokenId => uint256) public rewardGrowthInside;
    mapping(uint256 nfpTokenId => uint256) public lastUpdateTime;
    mapping(uint256 nfpTokenId => uint256) public rewards;

    uint256 public derivedSupply;
    mapping(address => uint256) public derivedBalances;

    // default snx staking contract implementation
    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => bool) public isReward;

    uint256 public fees0;
    uint256 public fees1;

    mapping(uint256 _blockNumber => mapping(address _user => bool)) userBlockLocked; // 1 action per block, eg deposit or withdraw

    modifier actionLock() {
        require(
            userBlockLocked[block.number][msg.sender] == false,
            "Action Locked"
        );
        userBlockLocked[block.number][msg.sender] = true;
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _pool,
        address _votingReward,
        address _kitten,
        address _voter,
        address _nfp,
        address _initialOwner
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __Ownable_init(_initialOwner);
        __ERC721Holder_init();
        __ReentrancyGuard_init();

        nfp = INonfungiblePositionManager(_nfp);
        pool = ICLPool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
        votingReward = IVotingReward(_votingReward);
        kitten = IERC20(_kitten);
        voter = _voter;

        tickSpacing = pool.tickSpacing();
    }

    function claimFees()
        external
        nonReentrant
        returns (uint256 claimed0, uint256 claimed1)
    {
        require(msg.sender == voter, "Not Voter");

        return _claimFees();
    }

    function _claimFees()
        internal
        returns (uint256 claimed0, uint256 claimed1)
    {
        uint256 token0BalBefore = token0.balanceOf(address(this));
        uint256 token1BalBefore = token1.balanceOf(address(this));
        (claimed0, claimed1) = pool.collectFees();
        uint256 token0BalAfter = token0.balanceOf(address(this));
        uint256 token1BalAfter = token1.balanceOf(address(this));

        if (claimed0 > 0 || claimed1 > 0) {
            uint256 _fees0 = fees0 + claimed0;
            uint256 _fees1 = fees1 + claimed1;

            if (token0BalAfter - token0BalBefore == claimed0) {
                if (_fees0 > 0) {
                    fees0 = 0;
                    token0.safeIncreaseAllowance(address(votingReward), _fees0);
                    votingReward.notifyRewardAmount(address(token0), _fees0);
                } else {
                    fees0 = _fees0;
                }
                emit ClaimFees(msg.sender, claimed0, 0);
            }
            if (token1BalAfter - token1BalBefore == claimed1) {
                if (_fees1 > 0) {
                    fees1 = 0;
                    token1.safeIncreaseAllowance(address(votingReward), _fees1);
                    votingReward.notifyRewardAmount(address(token1), _fees1);
                } else {
                    fees1 = _fees1;
                }
                emit ClaimFees(msg.sender, 0, claimed1);
            }
        }
    }

    function getReward(address account) external nonReentrant {
        address msgSender = msg.sender;
        require(
            msgSender == account || msgSender == voter,
            "Not Owner or Voter"
        );

        uint256[] memory nfpTokenIdList = userStakedNFPs[account].values();
        uint256 len = nfpTokenIdList.length;

        for (uint256 i; i < len; ) {
            _getReward(nfpTokenIdList[i], account);

            unchecked {
                ++i;
            }
        }
    }

    function getReward(uint256 nfpTokenId) external nonReentrant {
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
            kitten.safeTransfer(owner, reward);
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

    function earned(uint256 nfpTokenId) public view returns (uint256) {
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

        uint256 rewardGrowthInsideDelta;
        unchecked {
            rewardGrowthInsideDelta =
                rewardGrowthInsideCurrent -
                rewardGrowthInsideInitial;
        }

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
    function deposit(uint256 nfpTokenId) public nonReentrant actionLock {
        if (
            IVoter(voter).isGauge(address(this)) == false ||
            IVoter(voter).isAlive(address(this)) == false
        ) revert NotGaugeOrNotAlive();

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
            _token0 != address(token0) ||
            _token1 != address(token1) ||
            _tickSpacing != tickSpacing
        ) revert InvalidTokenId();

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

        emit Deposit(msg.sender, nfpTokenId, _liquidity);
    }

    function withdraw(uint256 nfpTokenId) public nonReentrant actionLock {
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

        emit Withdraw(msg.sender, nfpTokenId, _liquidity);
    }

    function left() external view returns (uint256) {
        if (block.timestamp >= periodFinish) return 0;
        uint256 _remaining = periodFinish - block.timestamp;
        return _remaining * rewardRate;
    }

    function notifyRewardAmount(uint256 amount) external nonReentrant {
        require(amount > 0);
        require(msg.sender == address(voter));

        _claimFees();
        pool.updateRewardsGrowthGlobal();

        address msgSender = msg.sender;
        uint256 timestamp = block.timestamp;
        uint256 epochDurationLeft = ProtocolTimeLibrary.epochNext(timestamp) -
            timestamp;

        kitten.safeTransferFrom(msgSender, address(this), amount);
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
        uint256 balance = IERC20(kitten).balanceOf(address(this));
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
