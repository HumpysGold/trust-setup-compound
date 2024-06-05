
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.23;

import {TargetFunctions} from "../../test/invariant/targets/TargetFunctions.sol";
import {CryticAsserts} from "@chimera/CryticAsserts.sol";

// anvil --hardfork shanghai -f https://eth-mainnet.g.alchemy.com/v2/kOTtPAuW53tAOR-uX27jHdhkLMh2JwcV
// echidna . --contract CryticForkTester --config echidna.yaml --rpc-url http://127.0.0.1:8545 --test-limit 1000000 --workers 8
// medusa fuzz
contract CryticForkTester is TargetFunctions, CryticAsserts {
    constructor() payable {
        setup();
    }
}
