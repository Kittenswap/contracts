// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICLGaugeFactory} from "./interfaces/ICLGaugeFactory.sol";
import {CLGauge} from "./CLGauge.sol";
import {ICLPool} from "../core/interfaces/ICLPool.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CLGaugeFactory is
    ICLGaugeFactory,
    UUPSUpgradeable,
    Ownable2StepUpgradeable
{
    address public implementation;
    address public ve;
    address public voter;
    address public nfp;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _ve,
        address _voter,
        address _nfp
    ) public initializer {
        __Ownable_init(msg.sender);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        implementation = address(new CLGauge());
        ve = _ve;
        voter = _voter;
        nfp = _nfp;
    }

    function createGauge(
        address _pool,
        address _internal_bribe,
        address _kitten,
        bool _isPool
    ) external returns (address) {
        require(msg.sender == voter, "Only voter can create gauge");

        CLGauge newGauge = CLGauge(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeCall(
                        CLGauge.initialize,
                        (
                            _pool,
                            _internal_bribe,
                            _kitten,
                            ve,
                            voter,
                            nfp,
                            _isPool
                        )
                    )
                )
            )
        );

        ICLPool(_pool).setGaugeAndPositionManager(address(newGauge), nfp);

        newGauge.transferOwnership(owner());

        return address(newGauge);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
