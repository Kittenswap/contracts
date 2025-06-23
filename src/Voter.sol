// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "./libraries/Math.sol";
import {VotingRewardFactory} from "./reward/VotingRewardFactory.sol";
import {RebaseReward} from "./reward/RebaseReward.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ProtocolTimeLibrary} from "./clAMM/libraries/ProtocolTimeLibrary.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGauge} from "./interfaces/IGauge.sol";
import {IGaugeFactory} from "./interfaces/IGaugeFactory.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IFactoryRegistry} from "./clAMM/core/interfaces/IFactoryRegistry.sol";
import {ICLFactory} from "./clAMM/core/interfaces/ICLFactory.sol";
import {ICLGaugeFactory} from "./clAMM/gauge/interfaces/ICLGaugeFactory.sol";
import {ICLPool} from "./clAMM/core/interfaces/ICLPool.sol";
import {IVotingReward} from "./interfaces/IVotingReward.sol";

contract Voter is
    IVoter,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant AUTHORIZED_ROLE = keccak256("AUTHORIZED_ROLE");
    uint256 public constant DURATION = ProtocolTimeLibrary.WEEK; // rewards are released over 7 days

    uint256 public periodInit;

    IVotingEscrow public veKitten;
    IERC20 public kitten;
    IFactoryRegistry public factoryRegistry;
    address public minter;
    RebaseReward public rebaseReward;

    uint256 public totalWeight; // total voting weight

    address[] public pools; // all pools viable for incentives
    mapping(address => address) public gauges; // pool => gauge
    mapping(address => address) public poolForGauge; // gauge => pool
    mapping(address => address) public votingReward; // gauge => VotingReward (fees & incentives)
    mapping(address => uint256) public weights; // pool => weight
    mapping(uint256 => mapping(address => uint256)) public votes; // nft => pool => votes
    mapping(uint256 => address[]) public poolVote; // nft => pools
    mapping(uint256 => uint256) public usedWeights; // nft => total voting weight of user
    mapping(uint256 => uint256) public lastVoted; // nft => timestamp of last vote, to ensure one vote per epoch
    mapping(address => bool) public isGauge;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isAlive;
    mapping(uint256 tokenId => bool) public isWhitelistedTokenId;

    uint256 public index;
    mapping(address => uint256) public supplyIndex;
    mapping(address => uint256) public claimable;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _veKitten,
        address _factoryRegistry,
        address _initialOwner
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __Ownable_init(_initialOwner);
        __AccessControl_init();
        __ReentrancyGuard_init();

        veKitten = IVotingEscrow(_veKitten);
        kitten = IERC20(veKitten.kitten());

        factoryRegistry = IFactoryRegistry(_factoryRegistry);

        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        _grantRole(AUTHORIZED_ROLE, _initialOwner);
    }

    modifier onlyNewEpoch(uint256 _tokenId) {
        if ((block.timestamp / DURATION) * DURATION <= lastVoted[_tokenId])
            revert AlreadyVoted();
        _;
    }

    /* public functions */
    function vote(
        uint256 tokenId,
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external onlyNewEpoch(tokenId) {
        uint256 blockTimestamp = block.timestamp;
        if (blockTimestamp < ProtocolTimeLibrary.epochVoteStart(blockTimestamp))
            revert NotOpenForVoting();
        if (
            blockTimestamp > ProtocolTimeLibrary.epochVoteEnd(blockTimestamp) &&
            isWhitelistedTokenId[tokenId] == false
        ) revert NotWhitelisted();
        if (veKitten.isApprovedOrOwner(msg.sender, tokenId) == false)
            revert NotApprovedOrOwner();
        if (_poolVote.length != _weights.length) revert InvalidParameters();

        lastVoted[tokenId] = blockTimestamp;
        _vote(tokenId, _poolVote, _weights);
    }

    function reset(uint256 _tokenId) external onlyNewEpoch(_tokenId) {
        if (veKitten.isApprovedOrOwner(msg.sender, _tokenId) == false)
            revert NotApprovedOrOwner();

        lastVoted[_tokenId] = block.timestamp;
        _reset(_tokenId);
        veKitten.abstain(_tokenId);
    }

    function poke(uint256 _tokenId) external {
        address[] memory _poolVote = poolVote[_tokenId];
        uint256 _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);

        for (uint256 i = 0; i < _poolCnt; i++) {
            _weights[i] = votes[_tokenId][_poolVote[i]];
        }

        _vote(_tokenId, _poolVote, _weights);
    }

    function notifyRewardAmount(uint256 amount) external {
        kitten.safeTransferFrom(msg.sender, address(this), amount);
        uint256 _ratio = (amount * 1e18) / totalWeight; // 1e18 adjustment is removed during claim
        if (_ratio > 0) {
            index += _ratio;
        }
        emit NotifyReward(msg.sender, address(kitten), amount);
    }

    function updateFor(address[] memory _gauges) external {
        for (uint256 i = 0; i < _gauges.length; i++) {
            _updateFor(_gauges[i]);
        }
    }

    function updateForRange(uint256 start, uint256 end) public {
        for (uint256 i = start; i < end; i++) {
            _updateFor(gauges[pools[i]]);
        }
    }

    function updateAll() external {
        updateForRange(0, pools.length);
    }

    function updateGauge(address _gauge) external {
        _updateFor(_gauge);
    }

    function claimEmissionsBatch(address[] memory _gauges) external {
        uint256 len = _gauges.length;
        for (uint256 i = 0; i < len; ) {
            IGauge(_gauges[i]).getReward(msg.sender);
            unchecked {
                ++i;
            }
        }
    }

    function claimVotingRewardBatch(
        address[] memory _votingRewardList,
        uint256 _tokenId
    ) external {
        if (veKitten.isApprovedOrOwner(msg.sender, _tokenId) == false)
            revert NotApprovedOrOwner();

        uint256 len = _votingRewardList.length;
        for (uint256 i = 0; i < len; ) {
            IVotingReward(_votingRewardList[i]).getRewardForOwner(_tokenId);
            unchecked {
                ++i;
            }
        }
    }

    function distribute(address _gauge) public nonReentrant {
        IMinter(minter).updatePeriod();
        _distribute(_gauge);
    }

    function distro() external nonReentrant {
        IMinter(minter).updatePeriod();
        _distributeRange(0, pools.length);
    }

    function distributeRange(
        uint256 start,
        uint256 finish
    ) public nonReentrant {
        IMinter(minter).updatePeriod();
        _distributeRange(start, finish);
    }

    function distribute(address[] memory _gauges) external {
        IMinter(minter).updatePeriod();
        for (uint256 x = 0; x < _gauges.length; x++) {
            _distribute(_gauges[x]);
        }
    }

    /* view functions */
    function length() external view returns (uint256) {
        return pools.length;
    }

    function poolVoteLength(uint256 _tokenId) external view returns (uint256) {
        return poolVote[_tokenId].length;
    }

    /* authorized functions */
    function init(
        address[] memory _tokens,
        address _minter
    ) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; i++) {
            _whitelist(_tokens[i], true);
        }
        minter = _minter;
        IMinter(minter).start();
    }

    function setMinter(address _minter) public onlyOwner {
        minter = _minter;
    }

    function setRebaseReward(address _rebaseReward) public onlyOwner {
        rebaseReward = RebaseReward(_rebaseReward);
    }

    function whitelist(
        address _token,
        bool _status
    ) public onlyRole(AUTHORIZED_ROLE) {
        _whitelist(_token, _status);
    }

    function setWhitelistTokenId(
        uint256 _tokenId,
        bool _isWhitelisted
    ) public onlyRole(AUTHORIZED_ROLE) {
        isWhitelistedTokenId[_tokenId] = _isWhitelisted;
    }

    function createGauge(
        address _poolFactory,
        address _pool
    ) external onlyRole(AUTHORIZED_ROLE) returns (address) {
        if (gauges[_pool] != address(0)) revert GaugeExists();

        bool isPair = IPairFactory(_poolFactory).isPair(_pool);
        if (isPair == false) revert InvalidPool();

        (address tokenA, address tokenB) = IPair(_pool).tokens();

        (address _gauge, address _votingReward) = _createGauge(
            _pool,
            _poolFactory,
            tokenA,
            tokenB,
            false
        );

        emit GaugeCreated(_gauge, msg.sender, _votingReward, _pool);
        return _gauge;
    }

    function createCLGauge(
        address _poolFactory,
        address _pool
    ) external onlyRole(AUTHORIZED_ROLE) returns (address) {
        if (gauges[_pool] != address(0)) revert GaugeExists();

        bool isPool = ICLFactory(_poolFactory).isPool(_pool);
        if (isPool == false) revert InvalidPool();

        address tokenA = ICLPool(_pool).token0();
        address tokenB = ICLPool(_pool).token1();

        (address _gauge, address _votingReward) = _createGauge(
            _pool,
            _poolFactory,
            tokenA,
            tokenB,
            true
        );
        emit GaugeCreated(_gauge, msg.sender, _votingReward, _pool);
        return _gauge;
    }

    function killGauge(address _gauge) external onlyRole(AUTHORIZED_ROLE) {
        _updateFor(_gauge);

        if (isAlive[_gauge] == false) revert GaugeDead();
        isAlive[_gauge] = false;
        uint256 _claimable = claimable[_gauge];
        claimable[_gauge] = 0;
        if (_claimable > 0) kitten.transfer(minter, _claimable);
        emit GaugeKilled(_gauge);
    }

    function reviveGauge(address _gauge) external onlyRole(AUTHORIZED_ROLE) {
        _updateFor(_gauge);

        if (isAlive[_gauge]) revert GaugeAlive();
        isAlive[_gauge] = true;
        supplyIndex[_gauge] = index;
        emit GaugeRevived(_gauge);
    }

    /* internal functions */
    function _vote(
        uint256 _tokenId,
        address[] memory _poolVote,
        uint256[] memory _weights
    ) internal {
        _reset(_tokenId);
        uint256 _poolCnt = _poolVote.length;
        uint256 _weight = veKitten.balanceOfNFT(_tokenId);
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = 0; i < _poolCnt; i++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint256 i = 0; i < _poolCnt; i++) {
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];

            if (_gauge == address(0)) revert NoGauge();

            if (isGauge[_gauge] == false) {
                revert NotValidGauge();
            } else {
                uint256 _poolWeight = (_weights[i] * _weight) /
                    _totalVoteWeight;
                if (votes[_tokenId][_pool] != 0) revert AlreadyVotedForPool();
                if (_poolWeight == 0) continue;
                _updateFor(_gauge);

                poolVote[_tokenId].push(_pool);

                weights[_pool] += _poolWeight;
                votes[_tokenId][_pool] += _poolWeight;
                IVotingReward(votingReward[_gauge])._deposit(
                    uint256(_poolWeight),
                    _tokenId
                );
                rebaseReward._deposit(uint256(_poolWeight), _tokenId);
                _usedWeight += _poolWeight;
                _totalWeight += _poolWeight;
                emit Voted(msg.sender, _tokenId, _poolWeight);
            }
        }
        if (_usedWeight > 0) veKitten.voting(_tokenId);
        totalWeight += uint256(_totalWeight);
        usedWeights[_tokenId] = uint256(_usedWeight);
    }

    function _reset(uint256 _tokenId) internal {
        address[] storage _poolVote = poolVote[_tokenId];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _poolVoteCnt; i++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_tokenId][_pool];
            address _gauge = gauges[_pool];

            if (_votes != 0) {
                _updateFor(gauges[_pool]);
                weights[_pool] -= _votes;
                votes[_tokenId][_pool] -= _votes;
                IVotingReward(votingReward[_gauge])._withdraw(
                    uint256(_votes),
                    _tokenId
                );
                rebaseReward._withdraw(uint256(_votes), _tokenId);
                _totalWeight += _votes;

                emit Abstained(_tokenId, _votes);
            }
        }
        totalWeight -= uint256(_totalWeight);
        usedWeights[_tokenId] = 0;
        delete poolVote[_tokenId];
    }

    function _updateFor(address _gauge) internal {
        address _pool = poolForGauge[_gauge];
        uint256 _supplied = weights[_pool];
        if (_supplied > 0) {
            uint256 _supplyIndex = supplyIndex[_gauge];
            uint256 _index = index; // get global index0 for accumulated distro
            supplyIndex[_gauge] = _index; // update _gauge current position to global position
            uint256 _delta = _index - _supplyIndex; // see if there is any difference that need to be accrued
            if (_delta > 0) {
                uint256 _share = (uint256(_supplied) * _delta) / 1e18; // add accrued difference for each supplied token
                if (isAlive[_gauge]) {
                    claimable[_gauge] += _share;
                } else {
                    IERC20(kitten).transfer(minter, _share);
                    IGauge(_gauge).claimFees(); // distribute accrued fees for killed gauges
                }
            }
        } else {
            supplyIndex[_gauge] = index; // new users are set to the default global state
        }
    }

    function _distribute(address _gauge) internal {
        _updateFor(_gauge); // should set claimable to 0 if killed
        uint256 _claimable = claimable[_gauge];
        if (_claimable > IGauge(_gauge).left() && _claimable / DURATION > 0) {
            claimable[_gauge] = 0;
            IGauge(_gauge).notifyRewardAmount(_claimable);
            emit DistributeReward(msg.sender, _gauge, _claimable);
        }
    }

    function _distributeRange(uint256 _start, uint256 _finish) internal {
        for (uint256 x = _start; x < _finish; x++) {
            _distribute(gauges[pools[x]]);
        }
    }

    function _whitelist(address _token, bool _status) internal {
        isWhitelisted[_token] = _status;
        emit Whitelisted(msg.sender, _token, _status);
    }

    function _createGauge(
        address _pool,
        address _poolFactory,
        address _tokenA,
        address _tokenB,
        bool _isCL
    ) internal returns (address _gauge, address _votingReward) {
        if (isWhitelisted[_tokenA] == false || isWhitelisted[_tokenB] == false)
            revert NotWhitelisted();

        (address votingRewardFactory, address gaugefactory) = IFactoryRegistry(
            factoryRegistry
        ).factoriesToPoolFactory(_poolFactory);

        _votingReward = VotingRewardFactory(votingRewardFactory)
            .createVotingReward();

        if (_isCL) {
            _gauge = ICLGaugeFactory(gaugefactory).createGauge(
                _pool,
                _votingReward
            );
        } else {
            _gauge = IGaugeFactory(gaugefactory).createGauge(
                _pool,
                _votingReward
            );
        }
        IVotingReward(_votingReward).grantNotifyRole(_gauge);

        kitten.approve(_gauge, type(uint256).max);
        votingReward[_gauge] = _votingReward;
        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        _updateFor(_gauge);
        pools.push(_pool);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
