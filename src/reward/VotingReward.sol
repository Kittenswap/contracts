// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Reward} from "./Reward.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IReward} from "../interfaces/IReward.sol";
import {IVotingReward} from "../interfaces/IVotingReward.sol";

contract VotingReward is IVotingReward, Reward {
    using SafeERC20 for IERC20;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _voter,
        address _veKitten,
        address _initialOwner
    ) public initializer {
        __Reward_init(_voter, _veKitten, _initialOwner);
    }

    function grantNotifyRole(
        address _account
    ) external override(Reward, IVotingReward) onlyVoter {
        _grantRole(NOTIFY_ROLE, _account);
    }

    function _getReward(
        uint256 _period,
        uint256 _tokenId,
        address _token,
        address _owner
    ) internal override {
        if (totalVotesInPeriod[_period] > 0) {
            uint256 reward = _earned(_period, _tokenId, _token);
            tokenIdRewardClaimedInPeriod[_period][_tokenId][_token] += reward;

            if (reward > 0) {
                IERC20(_token).safeTransfer(_owner, reward);
                emit ClaimReward(_period, _tokenId, _token, _owner);
            }
        }
    }
}
