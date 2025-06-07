pragma solidity ^0.8.23;

interface IGaugeFactory {
    function createGauge(address _lpToken) external returns (address);
}
