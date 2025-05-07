pragma solidity ^0.8.23;

interface ICLGauge {
    function notifyRewardAmount(address token, uint amount) external;
    function getReward(address account, address[] calldata tokens) external;
    function left(address token) external view returns (uint);
    function isForPair() external view returns (bool);
    function claimFees() external returns (uint claimed0, uint claimed1);
}
