// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IGoldComp {
    function approve(address, uint256) external;

    function balanceOf(address) external returns (uint256);

    function daysToWait() external view returns (uint256);

    function deposit(uint256) external;

    function queueWithdraw(uint256 _amount) external;

    function queuedWithdrawals(address, uint256)
        external
        view
        returns (uint256 amount, uint256 timestamp, uint256 releaseTimestamp, bool withdrawn);

    function withdraw() external;
}
