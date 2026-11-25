// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../../src/MultiPoolFarm.sol";
import "../mocks/MockToken.sol";

contract MultiPoolFarmHandler is Test {
    MultiPoolFarm public immutable multiPoolFarm;

    MockToken[] public poolTokens;
    address[] public actors;
    bytes32[] public poolIds;

    constructor(
        MultiPoolFarm _multiPoolFarm,
        MockToken[] memory _poolTokens,
        address[] memory _actors,
        bytes32[] memory _poolIds
    ) {
        multiPoolFarm = _multiPoolFarm;
        poolTokens = _poolTokens;
        actors = _actors;
        poolIds = _poolIds;
    }

    function stake(uint256 poolSeed, uint256 actorSeed, uint256 amount) public {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 pool = bound(poolSeed, 0, poolIds.length - 1);

        uint256 balance = poolTokens[pool].balanceOf(actor);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(actor);
        multiPoolFarm.stake(poolIds[pool], amount);
    }

    function skipTime(uint256 seconds_) public {
        seconds_ = bound(seconds_, 1, 7 days);
        skip(seconds_);
    }
}
