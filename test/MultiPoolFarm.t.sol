// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/MultiPoolFarm.sol";
import "./mocks/MockToken.sol";

contract MultiPoolFarmTest is Test {
    MultiPoolFarm public multiPoolFarm;
    MockToken public rewardToken;
    MockToken public stakingToken1;
    MockToken public stakingToken2;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    bytes32 public poolId1;
    bytes32 public poolId2;

    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;
    uint256 public constant REWARD_RATE = 1 * 10 ** 16; // 0.01 tokens per second

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy tokens
        rewardToken = new MockToken("Reward Token", "RWD", INITIAL_SUPPLY);
        stakingToken1 = new MockToken("Staking Token 1", "STK1", INITIAL_SUPPLY);
        stakingToken2 = new MockToken("Staking Token 2", "STK2", INITIAL_SUPPLY);

        // Deploy contracts
        multiPoolFarm = new MultiPoolFarm(address(rewardToken));

        // Transfer tokens to users
        stakingToken1.transfer(user1, 10000 * 10 ** 18);
        stakingToken1.transfer(user2, 10000 * 10 ** 18);
        stakingToken2.transfer(user1, 10000 * 10 ** 18);
        stakingToken2.transfer(user3, 10000 * 10 ** 18);

        // Transfer reward tokens to the farming pool
        rewardToken.transfer(address(multiPoolFarm), 500000 * 10 ** 18);

        // Create pools
        poolId1 = multiPoolFarm.createPool(address(stakingToken1), REWARD_RATE);
        poolId2 = multiPoolFarm.createPool(address(stakingToken2), REWARD_RATE * 2);

        // Approve tokens
        vm.startPrank(user1);
        stakingToken1.approve(address(multiPoolFarm), type(uint256).max);
        stakingToken2.approve(address(multiPoolFarm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        stakingToken1.approve(address(multiPoolFarm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user3);
        stakingToken2.approve(address(multiPoolFarm), type(uint256).max);
        vm.stopPrank();
    }

    function test_Constructor_RevertWhen_RewardTokenIsAddressZero() public {
        vm.expectRevert(MultiPoolFarm.ZeroAddress.selector);
        new MultiPoolFarm(address(0));
    }

    function test_CreatePool_StoresPoolData() public view {
        (address token1,, uint256 rewardRate1,,, bool isActive1) = multiPoolFarm.pools(poolId1);
        (address token2,, uint256 rewardRate2,,, bool isActive2) = multiPoolFarm.pools(poolId2);

        assertTrue(isActive1);
        assertTrue(isActive2);
        assertEq(token1, address(stakingToken1));
        assertEq(token2, address(stakingToken2));
        assertEq(rewardRate1, REWARD_RATE);
        assertEq(rewardRate2, REWARD_RATE * 2);
    }

    function test_CreatePool_PoolIdIsUnique() public {
        assertTrue(poolId1 != poolId2);

        vm.warp(block.timestamp + 1);
        bytes32 poolId3 = multiPoolFarm.createPool(address(stakingToken1), REWARD_RATE);

        assertTrue(poolId1 != poolId3);
    }

    function test_CreatePool_EmitsPoolCreated() public {
        uint256 newRate = REWARD_RATE * 3;
        bytes32 expectedId =
            keccak256(abi.encodePacked(address(stakingToken1), newRate, block.timestamp, block.chainid));

        vm.expectEmit(true, true, false, true);
        emit MultiPoolFarm.PoolCreated(expectedId, address(stakingToken1), newRate);
        multiPoolFarm.createPool(address(stakingToken1), newRate);
    }

    function test_CreatePool_RevertWhen_TokenIsAddressZero() public {
        vm.expectRevert(MultiPoolFarm.ZeroAddress.selector);
        multiPoolFarm.createPool(address(0), REWARD_RATE);
    }

    function test_CreatePool_RevertWhen_RewardRateIsZero() public {
        vm.expectRevert(MultiPoolFarm.RewardRateZero.selector);
        multiPoolFarm.createPool(address(stakingToken1), 0);
    }

    function test_CreatePool_RevertWhen_PoolAlreadyExists() public {
        // Same token, rate and block timestamp as in setUp
        vm.expectRevert(MultiPoolFarm.PoolAlreadyExists.selector);
        multiPoolFarm.createPool(address(stakingToken1), REWARD_RATE);
    }

    function test_CreatePool_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        multiPoolFarm.createPool(address(stakingToken1), REWARD_RATE);
    }

    function test_CreatePool_RevertWhen_TokenIsRewardToken() public {
        vm.expectRevert(MultiPoolFarm.StakeTokenIsRewardToken.selector);
        multiPoolFarm.createPool(address(rewardToken), REWARD_RATE);
    }

    function test_Stake_StoresUserAmountAndTotal() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        vm.stopPrank();

        (uint256 amount,,) = multiPoolFarm.userInfo(poolId1, user1);
        (, uint256 totalStaked,,,,) = multiPoolFarm.pools(poolId1);

        assertEq(amount, stakeAmount);
        assertEq(totalStaked, stakeAmount);
    }

    function test_Stake_IncreasesTotalStakedByToken() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        uint256 totalStakedByTokenBefore = multiPoolFarm.totalStakedByToken(address(stakingToken1));
        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        uint256 totalStakedByTokenAfter = multiPoolFarm.totalStakedByToken(address(stakingToken1));

        assertEq(totalStakedByTokenAfter, totalStakedByTokenBefore + stakeAmount);
    }

    function test_Stake_EmitsStaked() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit MultiPoolFarm.Staked(poolId1, user1, stakeAmount);
        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
    }

    function test_Stake_RevertWhen_PoolIsNotActive() public {
        uint256 stakeAmount = 1000 * 10 ** 18;
        multiPoolFarm.setPoolInactive(poolId1);

        vm.expectRevert(MultiPoolFarm.PoolInactive.selector);
        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
    }

    function test_Stake_RevertWhen_StakeAmountIsZero() public {
        uint256 stakeAmount = 0;

        vm.expectRevert(MultiPoolFarm.AmountZero.selector);
        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
    }

    function test_Withdraw_ReturnsStakedTokens() public {
        uint256 stakeAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 500 * 10 ** 18;

        vm.startPrank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        vm.warp(block.timestamp + 100);

        multiPoolFarm.withdraw(poolId1, withdrawAmount);
        vm.stopPrank();

        (uint256 amount,,) = multiPoolFarm.userInfo(poolId1, user1);
        (, uint256 totalStaked,,,,) = multiPoolFarm.pools(poolId1);

        assertEq(amount, stakeAmount - withdrawAmount);
        assertEq(totalStaked, stakeAmount - withdrawAmount);
        assertEq(stakingToken1.balanceOf(user1), 9000 * 10 ** 18 + withdrawAmount);
    }

    function test_Withdraw_DecreasesTotalStakedByToken() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        uint256 totalStakedByTokenBefore = multiPoolFarm.totalStakedByToken(address(stakingToken1));
        vm.prank(user1);
        multiPoolFarm.withdraw(poolId1, stakeAmount);
        uint256 totalStakedByTokenAfter = multiPoolFarm.totalStakedByToken(address(stakingToken1));

        assertEq(totalStakedByTokenAfter, totalStakedByTokenBefore - stakeAmount);
    }

    function test_Withdraw_ReturnsStakedTokensWhenPoolDeactivated() public {
        uint256 stakeAmount = 1000 * 10 ** 18;
        uint256 withdrawAmount = 500 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        multiPoolFarm.setPoolInactive(poolId1);
        vm.warp(block.timestamp + 100);

        vm.prank(user1);
        multiPoolFarm.withdraw(poolId1, withdrawAmount);

        (uint256 amount,,) = multiPoolFarm.userInfo(poolId1, user1);
        (, uint256 totalStaked,,,,) = multiPoolFarm.pools(poolId1);

        assertEq(amount, stakeAmount - withdrawAmount);
        assertEq(totalStaked, stakeAmount - withdrawAmount);
        assertEq(stakingToken1.balanceOf(user1), 9000 * 10 ** 18 + withdrawAmount);
    }

    function test_Withdraw_EmitsWithdrawn() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        vm.expectEmit(true, true, false, true);
        emit MultiPoolFarm.Withdrawn(poolId1, user1, stakeAmount);
        vm.prank(user1);
        multiPoolFarm.withdraw(poolId1, stakeAmount);
    }

    function test_Withdraw_RevertWhen_AmountExceedsStaked() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        vm.expectRevert(MultiPoolFarm.InsufficientStake.selector);
        multiPoolFarm.withdraw(poolId1, stakeAmount + 1);
        vm.stopPrank();
    }

    function test_Claim_TransferRewardsToUser() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        uint256 pendingRewards = multiPoolFarm.pendingRewards(poolId1, user1);
        assertGt(pendingRewards, 0);

        vm.startPrank(user1);
        multiPoolFarm.claim(poolId1);
        vm.stopPrank();

        assertGt(rewardToken.balanceOf(user1), 0);
    }

    function test_Claim_TransferRewardsToUserWhenPoolDeactivated() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        vm.stopPrank();

        skip(100);
        multiPoolFarm.setPoolInactive(poolId1);
        vm.warp(block.timestamp + 100);

        uint256 pendingRewards = multiPoolFarm.pendingRewards(poolId1, user1);
        assertGt(pendingRewards, 0);

        vm.startPrank(user1);
        multiPoolFarm.claim(poolId1);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(user1), REWARD_RATE * 100);
    }

    function test_Claim_TwoUsersClaimInSameBlockEachGetsShare() public {
        uint256 stakeAmount1 = 1000 * 10 ** 18;
        uint256 stakeAmount2 = 3 * stakeAmount1;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount1);

        vm.prank(user2);
        multiPoolFarm.stake(poolId1, stakeAmount2);

        vm.warp(block.timestamp + 100);

        vm.prank(user1);
        multiPoolFarm.claim(poolId1);

        vm.prank(user2);
        multiPoolFarm.claim(poolId1);

        uint256 totalRewards = REWARD_RATE * 100;

        assertEq(rewardToken.balanceOf(user1), totalRewards * stakeAmount1 / (stakeAmount1 + stakeAmount2));
        assertEq(rewardToken.balanceOf(user2), totalRewards * stakeAmount2 / (stakeAmount1 + stakeAmount2));
    }

    function test_Claim_LateStakerDoesNotReduceEarlierRewards() public {
        uint256 stakeAmount1 = 1000 * 10 ** 18;
        uint256 stakeAmount2 = 2 * stakeAmount1;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount1);

        skip(100);

        vm.prank(user2);
        multiPoolFarm.stake(poolId1, stakeAmount2);

        skip(100);

        vm.prank(user1);
        multiPoolFarm.claim(poolId1);

        uint256 expected = REWARD_RATE * 100 + REWARD_RATE * 100 * stakeAmount1 / (stakeAmount1 + stakeAmount2);

        assertApproxEqAbs(rewardToken.balanceOf(user1), expected, stakeAmount1 / 1e18);
    }

    function test_Claim_RevertWhen_NoRewards() public {
        vm.startPrank(user1);
        vm.expectRevert(MultiPoolFarm.NoRewardsToClaim.selector);
        multiPoolFarm.claim(poolId1);
        vm.stopPrank();
    }

    function test_UpdatePoolRewardRate_StoresNewRate() public {
        uint256 newRewardRate = REWARD_RATE * 2;

        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);

        (,, uint256 rewardRate,,,) = multiPoolFarm.pools(poolId1);
        assertEq(rewardRate, newRewardRate);
    }

    function test_UpdatePoolRewardRate_PaysOldRateBeforeChange() public {
        uint256 stakeAmount = 1000 * 10 ** 18;
        uint256 newRewardRate = REWARD_RATE * 2;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        skip(100);

        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);

        skip(100);

        vm.prank(user1);
        multiPoolFarm.claim(poolId1);

        uint256 expected = REWARD_RATE * 100 + newRewardRate * 100;

        assertEq(rewardToken.balanceOf(user1), expected);
    }

    function test_UpdatePoolRewardRate_TwoUsersShareNewRateProportionally() public {
        uint256 stakeAmount1 = 1000 * 10 ** 18;
        uint256 stakeAmount2 = 3000 * 10 ** 18;
        uint256 newRewardRate = REWARD_RATE * 2;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount1);
        vm.prank(user2);
        multiPoolFarm.stake(poolId1, stakeAmount2);

        skip(100);

        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);

        skip(100);

        vm.prank(user1);
        multiPoolFarm.claim(poolId1);

        vm.prank(user2);
        multiPoolFarm.claim(poolId1);

        uint256 totalRewards = REWARD_RATE * 100 + newRewardRate * 100;
        uint256 expected1 = totalRewards * stakeAmount1 / (stakeAmount1 + stakeAmount2);
        uint256 expected2 = totalRewards * stakeAmount2 / (stakeAmount1 + stakeAmount2);

        assertEq(rewardToken.balanceOf(user1), expected1);
        assertEq(rewardToken.balanceOf(user2), expected2);
        assertEq(rewardToken.balanceOf(user1) * 3, rewardToken.balanceOf(user2));
    }

    function test_UpdatePoolRewardRate_ZeroRateStopsNewRewards() public {
        uint256 stakeAmount = 1000 * 10 ** 18;
        uint256 newRewardRate = 0;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        skip(100);

        uint256 rewardBeforeZeroRate = multiPoolFarm.pendingRewards(poolId1, user1);
        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);

        skip(100);

        uint256 rewardAfterZeroRate = multiPoolFarm.pendingRewards(poolId1, user1);

        assertEq(rewardBeforeZeroRate, REWARD_RATE * 100);
        assertEq(rewardBeforeZeroRate, rewardAfterZeroRate);
    }

    function test_UpdatePoolRewardRate_NoStakersThenStakeGetsNoRetroactiveRewards() public {
        uint256 newRewardRate = REWARD_RATE * 2;
        uint256 stakeAmount = 1000 * 10 ** 18;

        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);
        skip(100);

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        uint256 user1PendingRewardsFirst = multiPoolFarm.pendingRewards(poolId1, user1);
        assertEq(user1PendingRewardsFirst, 0);

        skip(100);
        uint256 user1PendingRewardsSecond = multiPoolFarm.pendingRewards(poolId1, user1);
        assertEq(user1PendingRewardsSecond, newRewardRate * 100);
    }

    function test_UpdatePoolRewardRate_DoesNotAffectOtherPools() public {
        uint256 newRewardRate = REWARD_RATE * 2;
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        vm.prank(user3);
        multiPoolFarm.stake(poolId2, stakeAmount);

        skip(100);
        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);
        (,, uint256 rewardRatePool2Before,,,) = multiPoolFarm.pools(poolId2);
        skip(100);
        (,, uint256 rewardRatePool2After,,,) = multiPoolFarm.pools(poolId2);

        uint256 expectedUser3 = REWARD_RATE * 2 * 200;
        uint256 user3PendingRewards = multiPoolFarm.pendingRewards(poolId2, user3);
        uint256 expectedUser1 = REWARD_RATE * 100 + newRewardRate * 100;
        uint256 user1PendingRewards = multiPoolFarm.pendingRewards(poolId1, user1);

        assertEq(user3PendingRewards, expectedUser3);
        assertEq(user1PendingRewards, expectedUser1);
        assertEq(rewardRatePool2Before, rewardRatePool2After);
    }

    function test_UpdatePoolRewardRate_EmitsPoolUpdated() public {
        uint256 newRewardRate = REWARD_RATE * 2;
        vm.expectEmit(true, false, false, true);
        emit MultiPoolFarm.PoolUpdated(poolId1, newRewardRate);

        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);
    }

    function test_UpdatePoolRewardRate_RevertWhen_PoolIsInactive() public {
        uint256 newRewardRate = REWARD_RATE * 2;
        multiPoolFarm.setPoolInactive(poolId1);

        vm.expectRevert(MultiPoolFarm.PoolInactive.selector);
        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);
    }

    function test_UpdatePoolRewardRate_RevertWhen_CallerIsNotOwner() public {
        uint256 newRewardRate = REWARD_RATE * 2;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);
    }

    function test_PendingRewards_ProportionalToStake() public {
        uint256 stakeAmount1 = 1000 * 10 ** 18;
        uint256 stakeAmount2 = 2000 * 10 ** 18;

        vm.startPrank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount1);
        vm.stopPrank();

        vm.startPrank(user2);
        multiPoolFarm.stake(poolId1, stakeAmount2);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        uint256 pending1 = multiPoolFarm.pendingRewards(poolId1, user1);
        uint256 pending2 = multiPoolFarm.pendingRewards(poolId1, user2);

        assertGt(pending1, 0);
        assertGt(pending2, 0);

        assertGt(pending2, pending1);
    }

    function test_GetPoolEncodedData_ReturnsNonEmptyData() public view {
        bytes memory encodedData = multiPoolFarm.getPoolEncodedData(poolId1);

        assertGt(encodedData.length, 0);
    }

    function test_GetUserHash_DiffersByUserAndPool() public view {
        bytes32 userHash = multiPoolFarm.getUserHash(poolId1, user1);

        bytes32 userHash2 = multiPoolFarm.getUserHash(poolId1, user2);
        assertTrue(userHash != userHash2);

        bytes32 userHashPool2 = multiPoolFarm.getUserHash(poolId2, user1);
        assertTrue(userHash != userHashPool2);
    }

    function test_GetActivePools_ReturnsCreatedPools() public view {
        bytes32[] memory activePools = multiPoolFarm.getActivePools();
        assertEq(activePools.length, 2);
        assertEq(activePools[0], poolId1);
        assertEq(activePools[1], poolId2);

        assertEq(multiPoolFarm.getActivePoolsCount(), 2);
    }

    function test_RescueTokens_SendsSurplusTokenToOwner() public {
        uint256 amount = 1000 * 10 ** 18;
        stakingToken1.transfer(address(multiPoolFarm), amount);

        uint256 balanceBefore = stakingToken1.balanceOf(owner);

        multiPoolFarm.rescueTokens(address(stakingToken1), amount);

        uint256 balanceAfter = stakingToken1.balanceOf(owner);
        assertEq(balanceAfter, balanceBefore + amount);
    }

    function test_RescueTokens_EmitsTokensRescued() public {
        uint256 amount = 1000 * 10 ** 18;
        stakingToken1.transfer(address(multiPoolFarm), amount);

        vm.expectEmit(true, false, false, true);
        emit MultiPoolFarm.TokensRescued(address(stakingToken1), amount);

        multiPoolFarm.rescueTokens(address(stakingToken1), amount);
    }

    function test_RescueTokens_RevertWhen_CallerIsNotOwner() public {
        uint256 amount = 1000 * 10 ** 18;
        stakingToken1.transfer(address(multiPoolFarm), amount);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        multiPoolFarm.rescueTokens(address(stakingToken1), amount);
    }

    function test_RescueTokens_RevertWhen_TokenIsRewardToken() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.expectRevert(MultiPoolFarm.RewardTokenNotRescuable.selector);
        multiPoolFarm.rescueTokens(address(rewardToken), amount);
    }

    function test_RescueTokens_RevertWhen_AmountExceedsSurplus() public {
        uint256 stakeAmount = 1000 * 10 ** 18;
        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        stakingToken1.transfer(address(multiPoolFarm), stakeAmount / 2);

        vm.expectRevert(MultiPoolFarm.RescueExceedsSurplus.selector);
        multiPoolFarm.rescueTokens(address(stakingToken1), stakeAmount / 2 + 1);
    }

    function test_RescueTokens_RevertWhen_NoSurplusAndPoolsShareToken() public {
        uint256 stakeAmount = 1000 * 10 ** 18;
        bytes32 poolId3 = multiPoolFarm.createPool(address(stakingToken1), REWARD_RATE * 3);

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        vm.prank(user2);
        multiPoolFarm.stake(poolId3, stakeAmount);

        vm.expectRevert(MultiPoolFarm.RescueExceedsSurplus.selector);
        multiPoolFarm.rescueTokens(address(stakingToken1), 1);
    }

    function test_EmergencyWithdraw_ReturnsFullStake() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        skip(100);

        vm.prank(user1);
        multiPoolFarm.emergencyWithdraw(poolId1);

        (uint256 userAmount,,) = multiPoolFarm.userInfo(poolId1, user1);
        (, uint256 poolTotalStaked,,,,) = multiPoolFarm.pools(poolId1);

        assertEq(userAmount, 0);
        assertEq(poolTotalStaked, 0);
        assertEq(stakingToken1.balanceOf(user1), 10000 * 10 ** 18);
    }

    function test_EmergencyWithdraw_PaysNoRewards() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        skip(100);

        vm.prank(user1);
        multiPoolFarm.emergencyWithdraw(poolId1);

        assertEq(rewardToken.balanceOf(user1), 0);
    }

    function test_EmergencyWithdraw_ClearsRewardDebt() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user2);
        multiPoolFarm.stake(poolId1, stakeAmount);

        skip(100);
        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        skip(100);
        vm.prank(user1);
        multiPoolFarm.emergencyWithdraw(poolId1);

        uint256 userPendingRewards = multiPoolFarm.pendingRewards(poolId1, user1);
        assertEq(userPendingRewards, 0);
    }

    function test_EmergencyWithdraw_WorksWhenPoolIsInactive() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        skip(100);

        multiPoolFarm.setPoolInactive(poolId1);
        skip(100);

        vm.prank(user1);
        multiPoolFarm.emergencyWithdraw(poolId1);

        (uint256 userAmount,,) = multiPoolFarm.userInfo(poolId1, user1);
        (, uint256 poolTotalStaked,,,,) = multiPoolFarm.pools(poolId1);

        assertEq(userAmount, 0);
        assertEq(poolTotalStaked, 0);
        assertEq(stakingToken1.balanceOf(user1), 10000 * 10 ** 18);
    }

    function test_EmergencyWithdraw_WorksWhenRewardAccountingOverflows() public {
        uint256 stakeAmount = 1000 * 10 ** 18;
        uint256 newRewardRate = type(uint256).max / 1e18 + 1;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        skip(100);

        // Absurd rate: rewards * 1e18 overflows inside _updatePool()
        multiPoolFarm.updatePoolRewardRate(poolId1, newRewardRate);
        skip(1);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(user1);
        multiPoolFarm.withdraw(poolId1, stakeAmount);

        vm.prank(user1);
        multiPoolFarm.emergencyWithdraw(poolId1);

        (uint256 userAmount,,) = multiPoolFarm.userInfo(poolId1, user1);
        (, uint256 poolTotalStaked,,,,) = multiPoolFarm.pools(poolId1);

        assertEq(userAmount, 0);
        assertEq(poolTotalStaked, 0);
        assertEq(stakingToken1.balanceOf(user1), 10000 * 10 ** 18);
    }

    function test_EmergencyWithdraw_DecreasesTotalStakedByToken() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        uint256 totalStakedByTokenBefore = multiPoolFarm.totalStakedByToken(address(stakingToken1));
        vm.prank(user1);
        multiPoolFarm.emergencyWithdraw(poolId1);
        uint256 totalStakedByTokenAfter = multiPoolFarm.totalStakedByToken(address(stakingToken1));

        assertEq(totalStakedByTokenAfter, totalStakedByTokenBefore - stakeAmount);
    }

    function test_EmergencyWithdraw_EmitsEmergencyWithdrawn() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);

        skip(100);
        vm.expectEmit(true, true, false, true);
        emit MultiPoolFarm.EmergencyWithdrawn(poolId1, user1, stakeAmount);
        vm.prank(user1);
        multiPoolFarm.emergencyWithdraw(poolId1);
    }

    function test_EmergencyWithdraw_RevertWhen_NothingStaked() public {
        vm.expectRevert(MultiPoolFarm.NothingStaked.selector);
        vm.prank(user1);
        multiPoolFarm.emergencyWithdraw(poolId1);
    }

    function test_SetPoolInactive_DeactivatesThePool() public {
        (,,,,, bool poolIsActiveBefore) = multiPoolFarm.pools(poolId1);
        multiPoolFarm.setPoolInactive(poolId1);
        (,,,,, bool poolIsActiveAfter) = multiPoolFarm.pools(poolId1);

        assertTrue(poolIsActiveBefore);
        assertFalse(poolIsActiveAfter);
    }

    function test_SetPoolInactive_StopsNewRewards() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.prank(user1);
        multiPoolFarm.stake(poolId1, stakeAmount);
        skip(100);

        uint256 user1PendingRewardsBefore = multiPoolFarm.pendingRewards(poolId1, user1);
        multiPoolFarm.setPoolInactive(poolId1);
        skip(100);

        uint256 user1PendingRewardsAfter = multiPoolFarm.pendingRewards(poolId1, user1);
        (,, uint256 rewardRateAfter,,,) = multiPoolFarm.pools(poolId1);

        assertEq(rewardRateAfter, 0);
        assertEq(user1PendingRewardsBefore, user1PendingRewardsAfter);
        assertEq(user1PendingRewardsBefore, REWARD_RATE * 100);
    }

    function test_SetPoolInactive_EmitsPoolDeactivated() public {
        vm.expectEmit(true, false, false, true);
        emit MultiPoolFarm.PoolDeactivated(poolId1);

        multiPoolFarm.setPoolInactive(poolId1);
    }

    function test_SetPoolInactive_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        multiPoolFarm.setPoolInactive(poolId1);
    }

    function test_SetPoolInactive_RevertWhen_PoolIsInactive() public {
        multiPoolFarm.setPoolInactive(poolId1);

        vm.expectRevert(MultiPoolFarm.PoolInactive.selector);
        multiPoolFarm.setPoolInactive(poolId1);
    }
}
