// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../libraries/Math.sol";
import "../../interfaces/IBribe.sol";
import "../../interfaces/IERC20.sol";
import "./interfaces/ICLGauge.sol";
import "./interfaces/IPair.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IVotingEscrow.sol";

import {INonFungiblePositionManager} from "../periphery/interfaces/INonFungiblePositionManager.sol";

import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {ICLPool} from "../core/interfaces/ICLPool.sol";

import {FixedPoint128} from "../core/libraries/FixedPoint128.sol";

/* 
Changes to original Gauge to support CL:
- each CL NFP tokenId will replace "msg.sender" from the mappings
- nap CL NFP tokenId to msg.sender for deposit and withdrawals
- treat "liquidity" as "token" in "rewardPerTokenStored"
- treat CL NFP tokenId as "user" in "userRewardPerTokenStored"
 */

// Gauges are used to incentivize pools, they emit reward tokens over 7 days for staked LP tokens
contract CLGauge is ICLGauge {
    using EnumerableSet for EnumerableSet.UintSet;

    INonFungiblePositionManager public nfp;
    address public token0;
    address public token1;
    int24 public tickSpacing;

    mapping(address => EnumerableSet.UintSet) public userStakedNFPs;

    ICLPool public override pool;

    mapping(uint256 nfpTokenId => uint256) public rewardGrowthInside;
    mapping(uint256 nfpTokenId => uint256) public lastUpdateTime;

    mapping(uint256 nfpTokenId => uint256) public rewards;

    /* events */
    event Deposit(
        address indexed from,
        uint256 nfpTokenId,
        uint256 tokenId,
        uint256 liquidityStaked
    );

    /* errors */
    error CLGauge__InvalidTokenId();

    address public immutable stake; // the LP token that needs to be staked for rewards
    address public immutable _ve; // the ve token used for gauges
    address public immutable internal_bribe;
    address public immutable external_bribe;
    address public immutable voter;

    uint public derivedSupply;
    mapping(address => uint) public derivedBalances;

    bool public isForPair;

    uint internal constant DURATION = 7 days; // rewards are released over 7 days
    uint internal constant PRECISION = 10 ** 18;
    uint internal constant MAX_REWARD_TOKENS = 16;

    // default snx staking contract implementation
    mapping(address => uint) public rewardRate;
    mapping(address => uint) public periodFinish;
    mapping(address => uint) public lastUpdateTime;
    mapping(address => uint) public rewardPerTokenStored;

    mapping(address => mapping(address => uint)) public lastEarn;
    mapping(address => mapping(address => uint))
        public userRewardPerTokenStored;

    mapping(address => uint) public tokenIds;

    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    address[] public rewards;
    mapping(address => bool) public isReward;

    /// @notice A checkpoint for marking balance
    struct Checkpoint {
        uint timestamp;
        uint balanceOf;
    }

    /// @notice A checkpoint for marking reward rate
    struct RewardPerTokenCheckpoint {
        uint timestamp;
        uint rewardPerToken;
    }

    /// @notice A checkpoint for marking supply
    struct SupplyCheckpoint {
        uint timestamp;
        uint supply;
    }

    /// @notice A record of balance checkpoints for each account, by index
    mapping(address => mapping(uint => Checkpoint)) public checkpoints;
    /// @notice The number of checkpoints for each account
    mapping(address => uint) public numCheckpoints;
    /// @notice A record of balance checkpoints for each token, by index
    mapping(uint => SupplyCheckpoint) public supplyCheckpoints;
    /// @notice The number of checkpoints
    uint public supplyNumCheckpoints;
    /// @notice A record of balance checkpoints for each token, by index
    mapping(address => mapping(uint => RewardPerTokenCheckpoint))
        public rewardPerTokenCheckpoints;
    /// @notice The number of checkpoints for each token
    mapping(address => uint) public rewardPerTokenNumCheckpoints;

    uint public fees0;
    uint public fees1;

    event Withdraw(address indexed from, uint tokenId, uint amount);
    event NotifyReward(
        address indexed from,
        address indexed reward,
        uint amount
    );
    event ClaimFees(address indexed from, uint claimed0, uint claimed1);
    event ClaimRewards(address indexed from, uint amount);

    constructor(
        address _stake,
        address _internal_bribe,
        address _external_bribe,
        address __ve,
        address _voter,
        bool _forPair,
        address[] memory _allowedRewardTokens
    ) {
        stake = _stake;
        internal_bribe = _internal_bribe;
        external_bribe = _external_bribe;
        _ve = __ve;
        voter = _voter;
        isForPair = _forPair;

        for (uint i; i < _allowedRewardTokens.length; i++) {
            if (_allowedRewardTokens[i] != address(0)) {
                isReward[_allowedRewardTokens[i]] = true;
                rewards.push(_allowedRewardTokens[i]);
            }
        }
    }

    // simple re-entrancy check
    uint internal _unlocked = 1;
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    function claimFees() external lock returns (uint claimed0, uint claimed1) {
        return _claimFees();
    }

    function _claimFees() internal returns (uint claimed0, uint claimed1) {
        if (!isForPair) {
            return (0, 0);
        }
        (claimed0, claimed1) = IPair(stake).claimFees();
        if (claimed0 > 0 || claimed1 > 0) {
            uint _fees0 = fees0 + claimed0;
            uint _fees1 = fees1 + claimed1;
            (address _token0, address _token1) = IPair(stake).tokens();
            if (
                _fees0 > IBribe(internal_bribe).left(_token0) &&
                _fees0 / DURATION > 0
            ) {
                fees0 = 0;
                _safeApprove(_token0, internal_bribe, _fees0);
                IBribe(internal_bribe).notifyRewardAmount(_token0, _fees0);
            } else {
                fees0 = _fees0;
            }
            if (
                _fees1 > IBribe(internal_bribe).left(_token1) &&
                _fees1 / DURATION > 0
            ) {
                fees1 = 0;
                _safeApprove(_token1, internal_bribe, _fees1);
                IBribe(internal_bribe).notifyRewardAmount(_token1, _fees1);
            } else {
                fees1 = _fees1;
            }

            emit ClaimFees(msg.sender, claimed0, claimed1);
        }
    }

    function getReward(address account) external lock {
        require(
            msg.sender == account || msg.sender == voter,
            "Not Owner or Voter"
        );

        uint256[] memory nfpTokenIdList = userStakedNFPs[account].values();
        uint256 len = nfpTokenIdList.length;

        for (uint256 i; i < len; ) {
            _getReward(nfpTokenIdList[i]);

            unchecked {
                ++i;
            }
        }
    }

    function getReward(uint256 nfpTokenId) external lock {
        require(userStakedNFPs[msg.sender].contains(nfpTokenId), "Not Owner");

        _getReward(nfpTokenId);
    }

    function _getReward(uint256 nfpTokenId) internal {
        (, , , , , int24 _tickLower, int24 _tickUpper, , , , , ) = nfp
            .positions(nfpTokenId);

        _updateRewardForNfp(nfpTokenId, _tickLower, _tickUpper);

        uint256 reward = rewards[tokenId];

        if (reward > 0) {
            delete rewards[tokenId];
            IERC20(rewardToken).safeTransfer(owner, reward);
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
            tickLower,
            tickUpper,
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

            rewardGrowthGlobalX128 +=
                (reward * FixedPoint128.Q128) /
                pool.stakedLiquidity();
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

        ) = nft.positions(nfpTokenId);

        uint256 rewardGrowthInsideInitial = rewardGrowthInside[nfpTokenId];
        uint256 rewardGrowthInsideCurrent = pool.getRewardGrowthInside(
            _tickLower,
            _tickUpper,
            rewardGrowthGlobalX128
        );

        uint256 rewardGrowthInsideDelta = rewardPerTokenInsideX128 -
            rewardPerTokenInsideInitialX128;

        return (rewardGrowthInsideDelta * _liquidity) / FixedPoint128.Q128;
    }

    // deposit NFP tokenId
    function deposit(uint256 nfpTokenId, uint256 tokenId) public lock {
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

        nft.collect(
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
        pool.stake(int128(_liquidity), tickLower, tickUpper, true);

        // set initial reward growth as reference for calc rewards over time
        uint256 rewardGrowth = pool.getRewardGrowthInside(
            tickLower,
            tickUpper,
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

    function withdraw(uint amount) public {
        uint tokenId = 0;
        if (amount == balanceOf[msg.sender]) {
            tokenId = tokenIds[msg.sender];
        }
        withdrawToken(amount, tokenId);
    }

    function withdrawToken(uint amount, uint tokenId) public lock {
        _updateRewardForAllTokens();

        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        _safeTransfer(stake, msg.sender, amount);

        if (tokenId > 0) {
            require(tokenId == tokenIds[msg.sender]);
            tokenIds[msg.sender] = 0;
            IVoter(voter).detachTokenFromGauge(tokenId, msg.sender);
        } else {
            tokenId = tokenIds[msg.sender];
        }

        uint _derivedBalance = derivedBalances[msg.sender];
        derivedSupply -= _derivedBalance;
        _derivedBalance = derivedBalance(msg.sender);
        derivedBalances[msg.sender] = _derivedBalance;
        derivedSupply += _derivedBalance;

        _writeCheckpoint(msg.sender, derivedBalances[msg.sender]);
        _writeSupplyCheckpoint();

        IVoter(voter).emitWithdraw(tokenId, msg.sender, amount);
        emit Withdraw(msg.sender, tokenId, amount);
    }

    function left(address token) external view returns (uint) {
        if (block.timestamp >= periodFinish[token]) return 0;
        uint _remaining = periodFinish[token] - block.timestamp;
        return _remaining * rewardRate[token];
    }

    function notifyRewardAmount(address token, uint amount) external lock {
        require(token != stake);
        require(amount > 0);
        if (!isReward[token]) {
            require(
                IVoter(voter).isWhitelisted(token),
                "rewards tokens must be whitelisted"
            );
            require(
                rewards.length < MAX_REWARD_TOKENS,
                "too many rewards tokens"
            );
        }
        if (rewardRate[token] == 0)
            _writeRewardPerTokenCheckpoint(token, 0, block.timestamp);
        (
            rewardPerTokenStored[token],
            lastUpdateTime[token]
        ) = _updateRewardPerToken(token, type(uint).max, true);
        _claimFees();

        if (block.timestamp >= periodFinish[token]) {
            _safeTransferFrom(token, msg.sender, address(this), amount);
            rewardRate[token] = amount / DURATION;
        } else {
            uint _remaining = periodFinish[token] - block.timestamp;
            uint _left = _remaining * rewardRate[token];
            require(amount > _left);
            _safeTransferFrom(token, msg.sender, address(this), amount);
            rewardRate[token] = (amount + _left) / DURATION;
        }
        require(rewardRate[token] > 0);
        uint balance = IERC20(token).balanceOf(address(this));
        require(
            rewardRate[token] <= balance / DURATION,
            "Provided reward too high"
        );
        periodFinish[token] = block.timestamp + DURATION;
        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }

        emit NotifyReward(msg.sender, token, amount);
    }

    function swapOutRewardToken(
        uint i,
        address oldToken,
        address newToken
    ) external {
        require(msg.sender == IVotingEscrow(_ve).team(), "only team");
        require(rewards[i] == oldToken);
        isReward[oldToken] = false;
        isReward[newToken] = true;
        rewards[i] = newToken;
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
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
}
