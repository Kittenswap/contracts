pragma solidity ^0.8.23;

interface ICLGaugeFactory {
    function createGauge(
        address _pool,
        address _internal_bribe,
        address _kitten,
        bool _isPool
    ) external returns (address);
}
