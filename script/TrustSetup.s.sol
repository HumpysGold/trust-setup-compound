// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {TrustSetup} from "../src/TrustSetup.sol";

contract TrustSetupScript is Script {
    TrustSetup trustSetup;

    function run() public {
        uint256 pk = vm.envUint("PKEY");
        vm.startBroadcast(pk);

        trustSetup = new TrustSetup();
    }
}
