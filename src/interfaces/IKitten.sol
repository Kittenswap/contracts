pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IKitten is IERC20 {
    error NotMinter();

    function mint(address, uint) external;
    function minter() external returns (address);
}
