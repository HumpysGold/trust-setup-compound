// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IWeightedPool is IERC20 {
    function getInvariant() external view returns (uint256);

    function getLastPostJoinExitInvariant() external view returns (uint256);
}
