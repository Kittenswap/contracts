pragma solidity ^0.8.28;

interface IGaugeFactory {
    function createGauge(
        address _lpToken,
        address _votingReward
    ) external returns (address);
}
