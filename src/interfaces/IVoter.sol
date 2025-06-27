// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVoter {
    event GaugeCreated(
        address indexed gauge,
        address creator,
        address _votingReward,
        address indexed pool
    );
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event Voted(address indexed voter, uint tokenId, uint256 weight);
    event Abstained(uint tokenId, uint256 weight);
    event Deposit(
        address indexed lp,
        address indexed gauge,
        uint tokenId,
        uint amount
    );
    event Withdraw(
        address indexed lp,
        address indexed gauge,
        uint tokenId,
        uint amount
    );
    event NotifyReward(
        address indexed sender,
        address indexed reward,
        uint amount
    );
    event DistributeReward(
        address indexed sender,
        address indexed gauge,
        uint amount
    );
    event Attach(address indexed owner, address indexed gauge, uint tokenId);
    event Detach(address indexed owner, address indexed gauge, uint tokenId);
    event Whitelisted(
        address indexed whitelister,
        address indexed token,
        bool _status
    );

    error NotValidGauge();
    error NoGauge();
    error NotOpenForVoting();
    error NotWhitelisted();
    error GaugeExists();
    error InvalidPool();
    error GaugeDead();
    error GaugeAlive();
    error NotApprovedOrOwner();
    error AlreadyVoted();
    error InvalidParameters();
    error AlreadyVotedForPool();

    function isWhitelisted(address token) external view returns (bool);
    function notifyRewardAmount(uint amount) external;
    function distribute(address _gauge) external;
    function isGauge(address _gauge) external view returns (bool);
    function isAlive(address _gauge) external view returns (bool);
}
