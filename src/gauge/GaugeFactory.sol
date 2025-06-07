// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Gauge} from "./Gauge.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GaugeFactory is UUPSUpgradeable, Ownable2StepUpgradeable {
    address public implementation;
    address public kitten;
    address public voter;

    error NotVoter();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _kitten,
        address _voter,
        address _initialOwner
    ) public initializer {
        __Ownable_init(_initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        implementation = address(new Gauge());
        kitten = _kitten;
        voter = _voter;
    }

    function createGauge(address _lpToken) external returns (address) {
        if (msg.sender != voter) revert NotVoter();

        Gauge newGauge = Gauge(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeCall(
                        Gauge.initialize,
                        (_lpToken, kitten, voter, owner())
                    )
                )
            )
        );

        return address(newGauge);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
