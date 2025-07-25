// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMinter {
    error NotVoter();
    error TreasuryRateTooHigh();
    error RebaseRateTooHigh();

    function start() external;
    function updatePeriod() external returns (bool);
    function getCurrentPeriod() external view returns (uint256);
}
