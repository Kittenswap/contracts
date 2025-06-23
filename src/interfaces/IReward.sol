pragma solidity ^0.8.28;

interface IReward {
    event Deposit(uint256 _period, uint256 _amount, uint256 _tokenId);
    event Withdraw(uint256 _period, uint256 _amount, uint256 _tokenId);
    event NotifyReward(
        uint256 _period,
        address _from,
        address _token,
        uint256 amount
    );
    event IncentivizedReward(
        uint256 _period,
        address _from,
        address _token,
        uint256 amount
    );
    event ClaimReward(
        uint256 _period,
        uint256 _tokenId,
        address _token,
        address _to
    );

    error NotVoter();
    error NotWhitelistedRewardToken();
    error NotApprovedOrOwner();
    error FuturePeriodNotClaimable();

    /* only voter functions */
    function _deposit(uint256 _amount, uint256 _tokenId) external;
    function _withdraw(uint256 _amount, uint256 _tokenId) external;
    function getRewardForOwner(uint256 _tokenId) external;

    /* only authorized notifier functions*/
    function notifyRewardAmount(address _token, uint _amount) external;

    /* others */
    // function left(address token) external view returns (uint);
}
