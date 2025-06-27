// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICLGauge {
    event Deposit(
        address indexed from,
        uint256 nfpTokenId,
        uint256 liquidityStaked
    );
    event Withdraw(
        address indexed from,
        uint256 nfpTokenId,
        uint liquidityUnstaked
    );
    event NotifyReward(address indexed from, uint256 amount);
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
    event ClaimRewards(address indexed from, uint256 amount);

    error InvalidTokenId();
    error NotGaugeOrNotAlive();

    function notifyRewardAmount(uint256 amount) external;
    function getReward(address account) external;
    function left() external view returns (uint256);
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);
}
