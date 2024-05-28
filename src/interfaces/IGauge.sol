// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IGauge {
    function balanceOf(address) external returns (uint256);

    function claimable_reward(address, address) external view returns (uint256);

    function claim_rewards() external;

    function deposit(uint256) external;

    function totalSupply() external returns (uint256);

    function withdraw(uint256) external;
}
