pragma solidity ^0.8.23;

interface IMinter {
    error NotVoter();
    error TreasuryRateTooHigh();

    function start() external;
    function updatePeriod() external returns (bool);
}
