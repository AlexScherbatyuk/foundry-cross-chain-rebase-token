// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "@chainlink-ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink-ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract ConfigurePool is Script {
    function run(
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken,
        bool outbountRateLimiterIsEnabled,
        uint128 outboundRateLimitCapacity,
        uint128 outboundRateLimitRate,
        bool inbountRateLimiterIsEnabled,
        uint128 inboundRateLimitCapacity,
        uint128 inboundRateLimitRate
    ) public {
        vm.startBroadcast();
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePool),
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: outbountRateLimiterIsEnabled,
                capacity: outboundRateLimitCapacity,
                rate: outboundRateLimitRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: inbountRateLimiterIsEnabled,
                capacity: inboundRateLimitCapacity,
                rate: inboundRateLimitRate
            })
        });
        vm.stopBroadcast();
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
    }
}
