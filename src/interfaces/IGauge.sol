pragma solidity ^0.8.28;

interface IGauge {
    /* events */
    event ClaimAndNotifyFees(
        address indexed _from,
        uint256 _claimed0,
        uint256 _claimed1
    );

    /* errors */
    error NotVoterOrAuthorized();
    error NotOwnerOrVoter();
    error ActionLocked();
    error NotifyLessThanEqualToLeft();
    error ZeroRewardRate();
    error RewardRateExceedBalance();
    error ZeroAmount();
    error NotGaugeOrNotAlive();

    /* public functions */
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function getReward(address _account) external;

    /* view functions */
    function left() external view returns (uint256);

    /* authorized functions */
    function notifyRewardAmount(uint256 amount) external;
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);
}
