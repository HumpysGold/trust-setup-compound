
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {TrustInvestTargets} from "../../test/invariant/targets/TrustInvestTargets.sol";
import {TrustAdminTargets} from "../../test/invariant/targets/TrustAdminTargets.sol";
import {MaverickTargets} from "../../test/invariant/targets/MaverickTargets.sol";
import {CryticAsserts} from "@chimera/CryticAsserts.sol";

// anvil --hardfork shanghai -f https://eth-mainnet.g.alchemy.com/v2/kOTtPAuW53tAOR-uX27jHdhkLMh2JwcV
// echidna . --contract CryticForkTester --config echidna.yaml --rpc-url http://127.0.0.1:8545 --test-limit 1000000 --workers 8

contract CryticForkTester is
    MaverickTargets,
    TrustAdminTargets,
    TrustInvestTargets,
    CryticAsserts 
    {
    constructor() payable {
        setup();
    }
}
