// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import {JackpotPool} from "./JackpotPool.sol";
import {IJackpotPoolFactory} from "./interfaces/IJackpotPoolFactory.sol";

contract JackpotPoolFactory is IJackpotPoolFactory {
    /// @inheritdoc IJackpotPoolFactory
    function createPool(address jackpot_, bytes32 salt_) external returns (address pool) {
        // Check if pool already exists at this address
        bytes32 combinedSalt = _getSalt(jackpot_, msg.sender, salt_);
        address predictedAddress = Create2.computeAddress(
            combinedSalt, keccak256(abi.encodePacked(type(JackpotPool).creationCode, abi.encode(jackpot_, msg.sender)))
        );

        require(predictedAddress.code.length == 0, "Pool already exists");

        // Create the pool with CREATE2 for deterministic address
        pool = Create2.deploy(
            0, // no value sent
            combinedSalt,
            abi.encodePacked(type(JackpotPool).creationCode, abi.encode(jackpot_, msg.sender))
        );

        emit PoolCreated(pool, jackpot_, msg.sender, salt_);
    }

    /// @inheritdoc IJackpotPoolFactory
    function getPoolAddress(address jackpot_, address owner_, bytes32 salt_) external view returns (address pool) {
        return Create2.computeAddress(
            _getSalt(jackpot_, owner_, salt_),
            keccak256(abi.encodePacked(type(JackpotPool).creationCode, abi.encode(jackpot_, owner_)))
        );
    }

    /// @dev generates a unique salt combining jackpot, owner, and user-provided salt
    function _getSalt(address jackpot_, address owner_, bytes32 salt_) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(jackpot_, owner_, salt_));
    }
}
