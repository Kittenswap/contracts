pragma solidity ^0.8.23;

interface IGauge {
    /* public functions */
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function getReward(address _account) external;

    /* view functions */
    function left() external view returns (uint256);

    /* authorized functions */
    function notifyRewardAmount(uint256 amount) external;
}
