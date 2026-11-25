// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../../src/MultiPoolFarm.sol";
import "../mocks/MockToken.sol";
import "./MultiPoolFarmHandler.sol";

contract MultiPoolFarmInvariants is Test {
    MultiPoolFarm multiPoolFarm;
    MockToken rewardToken;
    MockToken stakingToken1;
    MockToken stakingToken2;
    MultiPoolFarmHandler handler;

    address[] actors;
    bytes32[] poolIds;
    MockToken[] poolTokens;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    uint256 public constant REWARD_RATE = 1 * 10 ** 16;
    uint256 public constant INITIAL_FUNDING = 500_000 * 10 ** 18;
    uint256 public constant USER_BALANCE = 100_000 * 10 ** 18;

    function setUp() public {
        rewardToken = new MockToken("Reward Token", "RWD", INITIAL_SUPPLY);
        stakingToken1 = new MockToken("Staking Token 1", "STK1", INITIAL_SUPPLY);
        stakingToken2 = new MockToken("Staking Token 2", "STK2", INITIAL_SUPPLY);
        multiPoolFarm = new MultiPoolFarm(address(rewardToken));

        rewardToken.approve(address(multiPoolFarm), INITIAL_FUNDING);
        multiPoolFarm.fundRewards(INITIAL_FUNDING);

        _addPool(stakingToken1, REWARD_RATE);
        _addPool(stakingToken2, REWARD_RATE * 2);
        _addPool(stakingToken1, REWARD_RATE / 2);

        actors.push(makeAddr("user1"));
        actors.push(makeAddr("user2"));
        actors.push(makeAddr("user3"));

        for(uint256 i = 0; i < actors.length; i++) {
            stakingToken1.mint(actors[i], USER_BALANCE);
            stakingToken2.mint(actors[i], USER_BALANCE);
            vm.startPrank(actors[i]);
            stakingToken1.approve(address(multiPoolFarm), type(uint256).max);
            stakingToken2.approve(address(multiPoolFarm), type(uint256).max);
            vm.stopPrank();
        }

        handler = new MultiPoolFarmHandler(multiPoolFarm, poolTokens, actors, poolIds);
        targetContract(address(handler));
    }

    function invariant_SumOfUserStakesEqualsPoolTotalStaked() public view {
        for(uint256 i = 0; i < poolIds.length; i++) {
            uint256 sumOfUserStakes = 0;

            for(uint256 j = 0; j < actors.length; j++) {
                (uint256 userAmount,,) = multiPoolFarm.userInfo(poolIds[i], actors[j]);
                sumOfUserStakes += userAmount;
            }
            
            (, uint256 poolTotalStaked,,,,) = multiPoolFarm.pools(poolIds[i]);
            assertEq(sumOfUserStakes, poolTotalStaked, "Sum of users != pool totalStaked.");
        }
    }

    function _addPool(MockToken token, uint256 rate) internal {
        poolIds.push(multiPoolFarm.createPool(address(token), rate));
        poolTokens.push(token);
        vm.warp(1);
    }
}