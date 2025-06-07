pragma solidity ^0.8.26;

import {IReward} from "./IReward.sol";

interface IVotingReward is IReward {
    function grantNotifyRole(address _account) external;
}
