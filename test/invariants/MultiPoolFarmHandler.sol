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
        uint256 poolIndex = bound(poolSeed, 0, poolIds.length - 1);

        uint256 balance = poolTokens[poolIndex].balanceOf(actor);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(actor);
        multiPoolFarm.stake(poolIds[poolIndex], amount);
    }

    function withdraw(uint256 poolSeed, uint256 actorSeed, uint256 amount) public {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 poolIndex = bound(poolSeed, 0, poolIds.length - 1);

        (uint256 actorAmount,,) = multiPoolFarm.userInfo(poolIds[poolIndex], actor);
        if (actorAmount == 0) return;
        amount = bound(amount, 1, actorAmount);

        vm.prank(actor);
        multiPoolFarm.withdraw(poolIds[poolIndex], amount);
    }

    function claim(uint256 poolSeed, uint256 actorSeed) public {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 poolIndex = bound(poolSeed, 0, poolIds.length - 1);

        if (multiPoolFarm.pendingRewards(poolIds[poolIndex], actor) == 0) return;

        vm.prank(actor);
        multiPoolFarm.claim(poolIds[poolIndex]);
    }

    function emergencyWithdraw(uint256 poolSeed, uint256 actorSeed) public {
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];
        uint256 poolIndex = bound(poolSeed, 0, poolIds.length - 1);

        (uint256 actorAmount,,) = multiPoolFarm.userInfo(poolIds[poolIndex], actor);
        if (actorAmount == 0) return;

        vm.prank(actor);
        multiPoolFarm.emergencyWithdraw(poolIds[poolIndex]);
    }

    function skipTime(uint256 seconds_) public {
        seconds_ = bound(seconds_, 1, 7 days);
        skip(seconds_);
    }
}
