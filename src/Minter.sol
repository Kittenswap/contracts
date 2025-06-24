// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Math} from "./libraries/Math.sol";
import {RebaseReward} from "./reward/RebaseReward.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ProtocolTimeLibrary} from "./clAMM/libraries/ProtocolTimeLibrary.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IKitten} from "./interfaces/IKitten.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

contract Minter is IMinter, UUPSUpgradeable, Ownable2StepUpgradeable {
    uint256 public constant WEEK = ProtocolTimeLibrary.WEEK; // allows minting once per week (reset every Thursday 00:00 UTC)

    uint256 internal constant EMISSION = 9_900; // 99%
    uint256 internal constant TAIL_EMISSION = 20; // 0.2% of total supply
    uint256 internal constant PRECISION = 10_000;
    uint256 public constant MAX_TREASURY_RATE = 500; // 5%
    uint256 public constant MAX_REBASE_RATE = 4_000; // 40%

    IKitten public kitten;
    IVoter public voter;
    IVotingEscrow public veKitten;
    RebaseReward public rebaseReward;
    uint256 public treasuryRate;
    uint256 public rebaseRate;
    uint256 public nextEmissions; // next epoch emissions
    uint256 public lastMintedPeriod;
    address public treasury;

    event Mint(
        address indexed _sender,
        uint256 _emissions,
        uint256 _circulatingSupply,
        uint256 _tailEmissions
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address __voter, // the voting & distribution system
        address _veKitten, // the ve(3,3) system that will be locked into
        address _rebaseReward, // the distribution system that ensures users aren't diluted
        address _treasury
    ) external initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __Ownable_init(msg.sender);

        treasuryRate = 500; // 5%
        rebaseRate = 3_000; // 30% bootstrap
        nextEmissions = (1_000_000_000 ether * 2) / 100; // epoch 1 starting emissions of 2% of initial total supply

        treasury = _treasury;
        veKitten = IVotingEscrow(_veKitten);
        kitten = IKitten(veKitten.kitten());
        voter = IVoter(__voter);
        rebaseReward = RebaseReward(_rebaseReward);

        // disable minter
        lastMintedPeriod = type(uint256).max;
    }

    /* public functions */
    function updatePeriod() external returns (bool) {
        uint256 currentPeriod = getCurrentPeriod();

        if (currentPeriod > lastMintedPeriod) {
            uint256 emissions = nextEmissions;
            nextEmissions = calculateNextEmissions(emissions);
            uint256 _tailEmissions = tailEmissions();

            if (_tailEmissions > emissions) {
                emissions = _tailEmissions;
            }

            uint256 rebase = calculateRebase(emissions);
            uint256 treasuryEmissions = ((emissions + rebase) * treasuryRate) /
                PRECISION;

            uint256 mintAmount = emissions + rebase + treasuryEmissions;
            uint256 kittenBal = kitten.balanceOf(address(this));
            if (kittenBal < mintAmount) {
                kitten.mint(address(this), mintAmount - kittenBal);
            }

            require(kitten.transfer(treasury, treasuryEmissions));
            kitten.approve(address(rebaseReward), rebase);
            rebaseReward.notifyRewardAmount(rebase);

            kitten.approve(address(voter), emissions);
            voter.notifyRewardAmount(emissions);

            emit Mint(
                msg.sender,
                emissions,
                circulatingSupply(),
                _tailEmissions
            );

            lastMintedPeriod = currentPeriod;

            return true;
        }
        return false;
    }

    /* view functions */
    function circulatingSupply() public view returns (uint256) {
        return kitten.totalSupply() - kitten.balanceOf(address(veKitten));
    }

    function calculateNextEmissions(
        uint256 _currentEmissions
    ) public pure returns (uint256) {
        return (_currentEmissions * EMISSION) / PRECISION;
    }

    function tailEmissions() public view returns (uint256) {
        return (circulatingSupply() * TAIL_EMISSION) / PRECISION;
    }

    function calculateRebase(uint256 _minted) public view returns (uint256) {
        return (_minted * rebaseRate) / PRECISION;
    }

    function getCurrentPeriod() public view returns (uint256) {
        return block.timestamp / WEEK;
    }

    /* authorized functions */
    function start() external {
        if (msg.sender != address(voter)) revert NotVoter();

        lastMintedPeriod = getCurrentPeriod(); // set the current period as epoch 0, and allows minting for epoch 1
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setTreasuryRate(uint256 _treasuryRate) external onlyOwner {
        if (_treasuryRate > MAX_TREASURY_RATE) revert TreasuryRateTooHigh();
        treasuryRate = _treasuryRate;
    }

    function setRebaseRate(uint256 _rebaseRate) external onlyOwner {
        if (_rebaseRate > MAX_REBASE_RATE) revert RebaseRateTooHigh();
        rebaseRate = _rebaseRate;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
