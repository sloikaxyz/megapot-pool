// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IJackpotPoolFactory {
    /// @dev emitted when a new pool is created
    event PoolCreated(address indexed pool, address indexed jackpot, address indexed owner, bytes32 salt);

    /// @dev creates a new JackpotPool instance
    /// @param jackpot_ address of the jackpot contract
    /// @param salt_ salt for deterministic address generation
    /// @return pool address of the created pool
    function createPool(address jackpot_, bytes32 salt_) external returns (address pool);

    /// @dev predicts the address of a pool before deployment
    /// @param jackpot_ address of the jackpot contract
    /// @param owner_ address of the pool owner
    /// @param salt_ salt for deterministic address generation
    /// @return pool predicted address of the pool
    function getPoolAddress(address jackpot_, address owner_, bytes32 salt_) external view returns (address pool);
}
