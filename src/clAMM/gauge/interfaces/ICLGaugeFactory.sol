pragma solidity ^0.8.23;

interface ICLGaugeFactory {
    function createGauge(
        address _pool,
        address _votingReward
    ) external returns (address);
}
