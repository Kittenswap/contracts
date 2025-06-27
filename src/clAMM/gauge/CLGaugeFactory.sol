// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ICLGaugeFactory} from "./interfaces/ICLGaugeFactory.sol";
import {CLGauge} from "./CLGauge.sol";
import {ICLPool} from "../core/interfaces/ICLPool.sol";

contract CLGaugeFactory is
    ICLGaugeFactory,
    UUPSUpgradeable,
    Ownable2StepUpgradeable
{
    address public implementation;
    address public veKitten;
    address public voter;
    address public nfp;
    address public kitten;

    error NotVoter();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _veKitten,
        address _voter,
        address _nfp,
        address _kitten
    ) public initializer {
        __Ownable_init(msg.sender);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        implementation = address(new CLGauge());
        veKitten = _veKitten;
        voter = _voter;
        nfp = _nfp;
        kitten = _kitten;
    }

    function createGauge(
        address _pool,
        address _votingReward
    ) external returns (address) {
        if (msg.sender != voter) revert NotVoter();

        CLGauge newGauge = CLGauge(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeCall(
                        CLGauge.initialize,
                        (_pool, _votingReward, kitten, voter, nfp, owner())
                    )
                )
            )
        );

        ICLPool(_pool).setGaugeAndPositionManager(address(newGauge), nfp);

        return address(newGauge);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
