// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MultiPoolFarm
 * @author Mario Flores
 * @notice Yield Farming contract demonstrating the use of abi.encodePacked
 *          to encode pool parameters and calculate unique identifiers
 */
contract MultiPoolFarm is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Structure to store pool information
    struct Pool {
        address token;
        uint256 totalStaked;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        bool isActive;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastClaimTime;
    }

    // Reward token
    IERC20 public immutable rewardToken;

    // Mapping of pools by their unique identifier
    mapping(bytes32 => Pool) public pools;

    // Mapping of user information by pool and address
    mapping(bytes32 => mapping(address => UserInfo)) public userInfo;

    // Mapping of total staked by the address of the token
    mapping(address => uint256) public totalStakedByToken;

    // List of all active pools
    bytes32[] public activePools;

    // Total reward token funded by the owner
    uint256 public totalFunded;

    // Total reward token paid to users
    uint256 public totalDistributed;

    /// @dev Emitted when the owner creates a pool
    event PoolCreated(bytes32 indexed poolId, address indexed token, uint256 rewardRate);

    /// @dev Emitted when a user stakes tokens in a pool
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);

    /// @dev Emitted when a user withdraws staked tokens from a pool
    event Withdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);

    /// @dev Emitted when pending rewards are paid to a user
    event RewardClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);

    /// @dev Emitted when the owner changes the reward rate of a pool
    event PoolUpdated(bytes32 indexed poolId, uint256 newRewardRate);

    /// @dev Emitted when a user exits a pool without rewards
    event EmergencyWithdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);

    /// @dev Emitted when the owner deactivates a pool
    event PoolDeactivated(bytes32 indexed poolId);

    /// @dev Emitted when the owner rescues tokens that were not owed to stakers nor commited as rewards
    event TokensRescued(address indexed token, uint256 amount);

    /// @dev Emited when the owner funds the farm with the reward token
    event RewardsFunded(address indexed funder, uint256 amount);

    /// @dev Thrown when the address is the zero address
    error ZeroAddress();

    /// @dev Thrown when the amount is zero
    error AmountZero();

    /// @dev Thrown when the reward rate is not greater than zero
    error RewardRateZero();

    /// @dev Thrown when a pool with the same identifier already exists
    error PoolAlreadyExists();

    /// @dev Thrown when the user has nothing staked in the pool
    error NothingStaked();

    /// @dev Thrown when using a pool that is not active
    error PoolInactive();

    /// @dev Thrown when the staked amount is lower than the requested amount
    error InsufficientStake();

    /// @dev Thrown when the user has no rewards to claim
    error NoRewardsToClaim();

    /// @dev Thrown when the staking token of a pool is the reward token
    error StakeTokenIsRewardToken();

    /// @dev Thrown when the rescued amount exceeds the tokens not owed to stakers
    error RescueExceedsSurplus();

    /// @dev Thrown when a payout exceeds the rewards funded and not yet distributed
    error InsufficientRewardBalance();

    /**
     * @dev The contract constructor
     * @param _rewardToken address of the reward token
     */
    constructor(address _rewardToken) Ownable(msg.sender) {
        if (_rewardToken == address(0)) revert ZeroAddress();
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @dev Creates a new yield farming pool
     * @param token address of the token to stake
     * @param rewardRate reward rate per second
     * @return poolId the unique pool identifier
     */
    function createPool(address token, uint256 rewardRate) external onlyOwner returns (bytes32 poolId) {
        if (token == address(0)) revert ZeroAddress();
        if (token == address(rewardToken)) revert StakeTokenIsRewardToken();
        if (rewardRate == 0) revert RewardRateZero();

        // The hash is an identifier, not a source of randomness
        // forge-lint: disable-next-line(weak-prng)
        poolId = keccak256(abi.encodePacked(token, rewardRate, block.timestamp, block.chainid));

        if (pools[poolId].token != address(0)) revert PoolAlreadyExists();

        pools[poolId] = Pool({
            token: token,
            totalStaked: 0,
            rewardRate: rewardRate,
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            isActive: true
        });

        activePools.push(poolId);

        emit PoolCreated(poolId, token, rewardRate);
    }

    /**
     * @dev Stake tokens in a specific pool
     * @param poolId Pool identifier
     * @param amount Amount of tokens to stake
     */
    function stake(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        if (!pool.isActive) revert PoolInactive();
        if (amount == 0) revert AmountZero();

        _updatePool(poolId);

        UserInfo storage user = userInfo[poolId][msg.sender];

        if (user.amount > 0) {
            uint256 pending = _calculatePendingRewards(poolId, msg.sender);
            if (pending > 0) {
                _payReward(msg.sender, pending);
                emit RewardClaimed(poolId, msg.sender, pending);
            }
        }

        IERC20(pool.token).safeTransferFrom(msg.sender, address(this), amount);

        user.amount += amount;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18;
        user.lastClaimTime = block.timestamp;

        pool.totalStaked += amount;
        totalStakedByToken[pool.token] += amount;

        emit Staked(poolId, msg.sender, amount);
    }

    /**
     * @dev Withdraw staked tokens from a pool
     * @param poolId Pool identifier
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        UserInfo storage user = userInfo[poolId][msg.sender];

        if (user.amount < amount) revert InsufficientStake();

        _updatePool(poolId);

        uint256 pending = _calculatePendingRewards(poolId, msg.sender);
        if (pending > 0) {
            _payReward(msg.sender, pending);
            emit RewardClaimed(poolId, msg.sender, pending);
        }

        user.amount -= amount;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18;

        pool.totalStaked -= amount;
        totalStakedByToken[pool.token] -= amount;

        IERC20(pool.token).safeTransfer(msg.sender, amount);

        emit Withdrawn(poolId, msg.sender, amount);
    }

    /**
     * @dev Claim pending rewards
     * @param poolId Pool identifier
     */
    function claim(bytes32 poolId) external nonReentrant {
        _updatePool(poolId);

        uint256 pending = _calculatePendingRewards(poolId, msg.sender);
        if (pending == 0) revert NoRewardsToClaim();

        UserInfo storage user = userInfo[poolId][msg.sender];
        user.rewardDebt = user.amount * pools[poolId].rewardPerTokenStored / 1e18;
        user.lastClaimTime = block.timestamp;

        _payReward(msg.sender, pending);
        emit RewardClaimed(poolId, msg.sender, pending);
    }

    /**
     * @dev Update the reward rate of a pool
     * @param poolId Pool identifier
     * @param newRewardRate New reward rate
     */
    function updatePoolRewardRate(bytes32 poolId, uint256 newRewardRate) external onlyOwner {
        Pool storage pool = pools[poolId];
        if (!pool.isActive) revert PoolInactive();

        _updatePool(poolId);
        pool.rewardRate = newRewardRate;

        emit PoolUpdated(poolId, newRewardRate);
    }

    /**
     * @dev Calculate the pending rewards of a user
     * @param poolId Pool identifier
     * @param user User address
     * @return Amount of pending rewards
     */
    function pendingRewards(bytes32 poolId, address user) external view returns (uint256) {
        Pool storage pool = pools[poolId];
        UserInfo storage userInfoData = userInfo[poolId][user];

        uint256 rewardPerTokenStored = pool.rewardPerTokenStored;

        if (pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
            uint256 rewards = timeElapsed * pool.rewardRate;
            rewardPerTokenStored += rewards * 1e18 / pool.totalStaked;
        }

        return userInfoData.amount * rewardPerTokenStored / 1e18 - userInfoData.rewardDebt;
    }

    /**
     * @dev Get encoded pool information for external use
     * @param poolId Pool identifier
     * @return encodedData Encoded pool data
     */
    function getPoolEncodedData(bytes32 poolId) external view returns (bytes memory encodedData) {
        Pool storage pool = pools[poolId];
        encodedData = abi.encodePacked(
            pool.token, pool.totalStaked, pool.lastUpdateTime, pool.rewardPerTokenStored, pool.isActive
        );
    }

    /**
     * @dev Create a unique hash for a user in a specific pool
     * @param poolId Pool identifier
     * @param user User address
     * @return userHash Unique user hash
     */
    function getUserHash(bytes32 poolId, address user) external pure returns (bytes32 userHash) {
        userHash = keccak256(abi.encodePacked(poolId, user, "YIELD_FARMING_USER"));
    }

    /**
     * @dev Get the total number of active pools
     * @return Number of active pools
     */
    function getActivePoolsCount() external view returns (uint256) {
        return activePools.length;
    }

    /**
     * @dev Get all active pools
     * @return Array with the identifiers of the active pools
     */
    function getActivePools() external view returns (bytes32[] memory) {
        return activePools;
    }

    /**
     * @dev Sends the owner the tokens that are not owed by the stakers nor commited as rewards
     * @param token Address of the token to rescue
     * @param amount Amount to rescue
     */
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        uint256 committed = token == address(rewardToken) ? totalFunded - totalDistributed : totalStakedByToken[token];
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        uint256 surplus = tokenBalance - committed;

        if (amount > surplus) revert RescueExceedsSurplus();

        IERC20(token).safeTransfer(owner(), amount);

        emit TokensRescued(token, amount);
    }

    /**
     * @dev Withdraws the whole stake and gives up pending rewards
     * @param poolId Pool identifier
     */
    function emergencyWithdraw(bytes32 poolId) external nonReentrant {
        UserInfo storage user = userInfo[poolId][msg.sender];
        if (user.amount == 0) revert NothingStaked();

        // _updatePool is skipped on purpose: the exit must work even if reward accounting reverts
        Pool storage pool = pools[poolId];
        uint256 userAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked -= userAmount;
        totalStakedByToken[pool.token] -= userAmount;

        IERC20(pool.token).safeTransfer(msg.sender, userAmount);

        emit EmergencyWithdrawn(poolId, msg.sender, userAmount);
    }

    /**
     * @dev Deactivates the pool and stops new rewards
     * @param poolId Pool identifier
     */
    function setPoolInactive(bytes32 poolId) external onlyOwner {
        Pool storage pool = pools[poolId];
        if (!pool.isActive) revert PoolInactive();

        _updatePool(poolId);
        pool.rewardRate = 0;
        pool.isActive = false;

        emit PoolDeactivated(poolId);
    }

    /**
     * @dev Funds the farm with reward token
     * @param amount Amount of reward token to fund
     */
    function fundRewards(uint256 amount) external onlyOwner {
        if (amount == 0) revert AmountZero();

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        totalFunded += amount;

        emit RewardsFunded(msg.sender, amount);
    }

    /**
     * @dev Update the pool state
     * @param poolId Pool identifier
     */
    function _updatePool(bytes32 poolId) internal {
        Pool storage pool = pools[poolId];

        if (pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
            uint256 rewards = timeElapsed * pool.rewardRate;
            pool.rewardPerTokenStored += rewards * 1e18 / pool.totalStaked;
        }
        pool.lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Pays rewards to a user, only from funded rewards
     * @param to Recipient address
     * @param amount Amount to pay
     */
    function _payReward(address to, uint256 amount) internal {
        if (totalDistributed + amount > totalFunded) revert InsufficientRewardBalance();

        totalDistributed += amount;
        rewardToken.safeTransfer(to, amount);
    }

    /**
     * @dev Calculate the pending rewards of a user
     * @param poolId Pool identifier
     * @param user User address
     * @return Amount of pending rewards
     */
    function _calculatePendingRewards(bytes32 poolId, address user) internal view returns (uint256) {
        Pool storage pool = pools[poolId];
        UserInfo storage userInfoData = userInfo[poolId][user];

        uint256 rewardPerTokenStored = pool.rewardPerTokenStored;

        return userInfoData.amount * rewardPerTokenStored / 1e18 - userInfoData.rewardDebt;
    }
}
