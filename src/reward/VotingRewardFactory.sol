// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VotingReward} from "./VotingReward.sol";

contract VotingRewardFactory is UUPSUpgradeable, Ownable2StepUpgradeable {
    /* errors */
    error NotVoter();

    address public implementation;
    address public veKitten;
    address public voter;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _veKitten,
        address _voter,
        address _initialOwner
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __Ownable_init(_initialOwner);

        implementation = address(new VotingReward());
        veKitten = _veKitten;
        voter = _voter;
    }

    function createVotingReward() external returns (address) {
        if (msg.sender != voter) revert NotVoter();

        VotingReward newVotingReward = VotingReward(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeCall(
                        VotingReward.initialize,
                        (voter, veKitten, owner())
                    )
                )
            )
        );

        return address(newVotingReward);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
