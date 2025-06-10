pragma solidity ^0.8.28;

interface IGaugeFactory {
    function createGauge(address _lpToken) external returns (address);
}
