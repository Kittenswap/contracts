// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IFactoryRegistry} from "../core/interfaces/IFactoryRegistry.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/// @custom:oz-upgrades
contract FactoryRegistry is
    IFactoryRegistry,
    UUPSUpgradeable,
    Ownable2StepUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address _poolFactory => address _gaugeFactory) public gaugeFactory;
    mapping(address _poolFactory => address _votingRewardsFactory)
        public votingRewardsFactory;

    EnumerableSet.AddressSet poolFactorySet;

    error FactoryRegistry__InvalidParameters();

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __Ownable2Step_init();
    }

    function approve(
        address _poolFactory,
        address _votingRewardsFactory,
        address _gaugeFactory
    ) public onlyOwner {
        address zeroAddress = address(0);
        if (
            _poolFactory == zeroAddress ||
            _votingRewardsFactory == zeroAddress ||
            _gaugeFactory == zeroAddress
        ) revert FactoryRegistry__InvalidParameters();

        poolFactorySet.add(_poolFactory);
        votingRewardsFactory[_poolFactory] = _votingRewardsFactory;
        gaugeFactory[_poolFactory] = _gaugeFactory;
    }

    function unapprove(address _poolFactory) external onlyOwner {
        if (isPoolFactoryApproved(_poolFactory) == false)
            revert FactoryRegistry__InvalidParameters();

        poolFactorySet.remove(_poolFactory);
        delete votingRewardsFactory[_poolFactory];
        delete gaugeFactory[_poolFactory];
    }

    function isPoolFactoryApproved(
        address _poolFactory
    ) public view returns (bool) {
        return poolFactorySet.contains(_poolFactory);
    }

    function factoriesToPoolFactory(
        address poolFactory
    )
        public
        view
        returns (address _votingRewardsFactory, address _gaugeFactory)
    {
        _votingRewardsFactory = votingRewardsFactory[poolFactory];
        _gaugeFactory = gaugeFactory[poolFactory];
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
