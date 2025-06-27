// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library LibRebaseRewardStorage {
    struct Layout {
        IERC20 kitten;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("kittenswap.contracts.storage.RebaseReward");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
