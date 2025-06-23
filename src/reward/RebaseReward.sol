// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRebaseReward} from "../interfaces/IRebaseReward.sol";
import {IReward} from "../interfaces/IReward.sol";

import {Reward} from "./Reward.sol";
import {LibRebaseRewardStorage} from "./libraries/LibRebaseRewardStorage.sol";

contract RebaseReward is IRebaseReward, Reward {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _voter,
        address _veKitten,
        address _initialOwner
    ) public initializer {
        LibRebaseRewardStorage.Layout storage s = LibRebaseRewardStorage
            .layout();

        __Reward_init(_voter, _veKitten, _initialOwner);
        s.kitten = IERC20(veKitten.kitten());
        s.kitten.approve(_veKitten, type(uint256).max);
    }

    function grantNotifyRole(
        address _account
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(NOTIFY_ROLE, _account);
    }

    function notifyRewardAmount(uint256 _amount) external {
        notifyRewardAmount(address(kitten()), _amount);
    }

    function notifyRewardAmount(
        address _token,
        uint256 _amount
    ) public override(Reward, IReward) {
        if (_token != address(kitten())) revert NotKitten();

        Reward.notifyRewardAmount(_token, _amount);
    }

    function incentivize(address _token, uint256 _amount) public override {
        if (_token != address(kitten())) revert NotKitten();

        Reward.incentivize(_token, _amount);
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
                (int128 amount, uint256 end) = veKitten.locked(_tokenId);
                if (
                    _tokenId <= veKitten.tokenId() &&
                    amount > 0 &&
                    end > block.timestamp
                ) {
                    veKitten.deposit_for(_tokenId, reward);
                } else {
                    veKitten.create_lock_for(
                        reward,
                        veKitten.MAXTIME(),
                        _owner
                    );
                }

                emit ClaimReward(_period, _tokenId, _token, _owner);
            }
        }
    }

    function kitten() public view returns (IERC20 _kitten) {
        _kitten = LibRebaseRewardStorage.layout().kitten;
    }
}
