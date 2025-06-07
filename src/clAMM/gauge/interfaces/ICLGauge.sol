pragma solidity ^0.8.23;

interface ICLGauge {
    function notifyRewardAmount(uint256 amount) external;
    function getReward(address account, address[] calldata tokens) external;
    function left() external view returns (uint256);
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);
}
