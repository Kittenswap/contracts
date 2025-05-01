pragma solidity ^0.8.23;

interface ICLGaugeFactory {
    function createGauge(
        address,
        address,
        address,
        address,
        bool,
        address[] memory
    ) external returns (address);
}
