// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IKitten} from "./interfaces/IKitten.sol";

contract Kitten is
    IKitten,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ERC20Upgradeable
{
    address public minter;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __Ownable_init(msg.sender);
        __ERC20_init("Kittenswap", "KITTEN");

        // 1B (1,000,000,000) KITTEN initial total supply
        _mint(msg.sender, 1_000_000_000 ether);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function mint(address _account, uint256 _amount) external {
        if (msg.sender != minter) revert NotMinter();
        _mint(_account, _amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
