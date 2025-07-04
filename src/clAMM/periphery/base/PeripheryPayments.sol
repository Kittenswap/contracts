// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import "openzeppelin-contracts-v3.4.2/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IPeripheryPayments.sol";
import "../interfaces/external/IWETH9.sol";

import "../libraries/TransferHelper.sol";

import "./PeripheryImmutableState.sol";

import {ReentrancyGuard} from "openzeppelin-contracts-v3.4.2/contracts/utils/ReentrancyGuard.sol";

abstract contract PeripheryPayments is IPeripheryPayments, PeripheryImmutableState, ReentrancyGuard {
    receive() external payable {
        require(msg.sender == WETH9, "NW9");
    }

    /// @inheritdoc IPeripheryPayments
    function unwrapWETH9(uint256 amountMinimum, address recipient) public payable override nonReentrant {
        uint256 balanceWETH9 = IWETH9(WETH9).balanceOf(address(this));
        require(balanceWETH9 >= amountMinimum, "IW"); // insufficient weth

        if (balanceWETH9 > 0) {
            IWETH9(WETH9).withdraw(balanceWETH9);
            TransferHelper.safeTransferETH(recipient, balanceWETH9);
        }
    }

    /// @inheritdoc IPeripheryPayments
    function sweepToken(address token, uint256 amountMinimum, address recipient) public payable override nonReentrant {
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        require(balanceToken >= amountMinimum, "IT"); // insufficient token

        if (balanceToken > 0) {
            TransferHelper.safeTransfer(token, recipient, balanceToken);
        }
    }

    /// @inheritdoc IPeripheryPayments
    function refundETH() public payable override nonReentrant {
        if (address(this).balance > 0) TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function pay(address token, address payer, address recipient, uint256 value) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // pay with WETH9
            IWETH9(WETH9).deposit{value: value}(); // wrap only what is needed to pay
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
