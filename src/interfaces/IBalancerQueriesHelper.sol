// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IBalancerQueriesHelper {
    struct SingleSwap {
        bytes32 poolId;
        uint8 kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    function querySwap(SingleSwap memory singleSwap, FundManagement memory funds) external returns (uint256);
}
