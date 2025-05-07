// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./libraries/Math.sol";
import "./interfaces/IMinter.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/IKitten.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IVotingEscrow.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

// codifies the minting rules as per ve(3,3), abstracted from the token to support any token that allows minting

contract Minter is IMinter, UUPSUpgradeable, Ownable2StepUpgradeable {
    uint internal constant WEEK = 86400 * 7; // allows minting once per week (reset every Thursday 00:00 UTC)
    uint internal constant EMISSION = 990; // 99%
    uint internal constant TAIL_EMISSION = 2;
    uint internal constant PRECISION = 1000;
    IKitten public _kitten;
    IVoter public _voter;
    IVotingEscrow public _ve;
    IRewardsDistributor public _rewards_distributor;
    uint public weekly;
    uint public active_period;
    uint internal constant LOCK = 86400 * 7 * 52 * 2;

    address internal _initializer;
    address public team;
    address public pendingTeam;
    uint public teamRate;
    uint public constant MAX_TEAM_RATE = 50; // 50 bps = 0.05%

    event Mint(
        address indexed sender,
        uint weekly,
        uint circulating_supply,
        uint circulating_emission
    );

    function initialize(
        address __voter, // the voting & distribution system
        address __ve, // the ve(3,3) system that will be locked into
        address __rewards_distributor // the distribution system that ensures users aren't diluted
    ) external initializer {
        _initializer = msg.sender;
        team = msg.sender;
        teamRate = 30; // 30 bps = 0.03%
        _kitten = IKitten(IVotingEscrow(__ve).token());
        _voter = IVoter(__voter);
        _ve = IVotingEscrow(__ve);
        _rewards_distributor = IRewardsDistributor(__rewards_distributor);
        active_period = ((block.timestamp + (2 * WEEK)) / WEEK) * WEEK;

        weekly = (1_000_000_000 ether * 2) / 100; // epoch 1 starting emissions of 2% of initial total supply

        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function init() external {
        require(_initializer == msg.sender, "not initializer");
        _initializer = address(0);
        active_period = ((block.timestamp) / WEEK) * WEEK; // allow minter.update_period() to mint new emissions THIS Thursday
    }

    function setTeam(address _team) external {
        require(msg.sender == team, "not team");
        pendingTeam = _team;
    }

    function acceptTeam() external {
        require(msg.sender == pendingTeam, "not pending team");
        team = pendingTeam;
    }

    function setTeamRate(uint _teamRate) external {
        require(msg.sender == team, "not team");
        require(_teamRate <= MAX_TEAM_RATE, "rate too high");
        teamRate = _teamRate;
    }

    // calculate circulating supply as total token supply - locked supply
    function circulating_supply() public view returns (uint) {
        return _kitten.totalSupply() - _ve.totalSupply();
    }

    // emission calculation is 1% of available supply to mint adjusted by circulating / total supply
    function calculate_emission() public view returns (uint) {
        return (weekly * EMISSION) / PRECISION;
    }

    // weekly emission takes the max of calculated (aka target) emission versus circulating tail end emission
    function weekly_emission() public view returns (uint) {
        return Math.max(calculate_emission(), circulating_emission());
    }

    // calculates tail end (infinity) emissions as 0.2% of total supply
    function circulating_emission() public view returns (uint) {
        return (circulating_supply() * TAIL_EMISSION) / PRECISION;
    }

    // calculate inflation and adjust ve balances accordingly
    function calculate_growth(uint _minted) public view returns (uint) {
        uint _veTotal = _ve.totalSupply();
        uint _kittenTotal = _kitten.totalSupply();
        return
            (((((_minted * _veTotal) / _kittenTotal) * _veTotal) /
                _kittenTotal) * _veTotal) /
            _kittenTotal /
            2;
    }

    // update period can only be called once per cycle (1 week)
    function update_period() external returns (uint) {
        uint _period = active_period;
        if (block.timestamp >= _period + WEEK && _initializer == address(0)) {
            // only trigger if new week
            _period = (block.timestamp / WEEK) * WEEK;
            active_period = _period;
            weekly = weekly_emission();

            uint _growth = calculate_growth(weekly);
            uint _teamEmissions = (teamRate * (_growth + weekly)) /
                (PRECISION - teamRate);
            uint _required = _growth + weekly + _teamEmissions;
            uint _balanceOf = _kitten.balanceOf(address(this));
            if (_balanceOf < _required) {
                _kitten.mint(address(this), _required - _balanceOf);
            }

            require(_kitten.transfer(team, _teamEmissions));
            require(_kitten.transfer(address(_rewards_distributor), _growth));
            _rewards_distributor.checkpoint_token(); // checkpoint token balance that was just minted in rewards distributor
            _rewards_distributor.checkpoint_total_supply(); // checkpoint supply

            _kitten.approve(address(_voter), weekly);
            _voter.notifyRewardAmount(weekly);

            emit Mint(
                msg.sender,
                weekly,
                circulating_supply(),
                circulating_emission()
            );
        }
        return _period;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
