pragma solidity ^0.8.28;

import {IReward} from "./IReward.sol";

interface IVotingReward is IReward {
    function grantNotifyRole(address _account) external;
}
