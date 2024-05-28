// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IOracle {
    function latestRoundData() external returns (uint80, int256, uint256, uint256, uint80);
}
