// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBaseJackpotPlay} from "../../src/interfaces/IBaseJackpotPlay.sol";

contract MockJackpot is IBaseJackpotPlay {
    using SafeERC20 for IERC20;

    address public immutable override token;
    uint256 public override ticketPrice = 1e6; // 1 token with 6 decimals
    uint256 public override feeBps = 500; // 5% fee
    uint256 public override roundDurationInSeconds = 1 days;
    uint256 public override lastJackpotEndTime;

    mapping(address => User) private _users;
    uint256 public jackpotAmount;
    address[] private _roundParticipants;

    constructor(address token_) {
        token = token_;
        lastJackpotEndTime = block.timestamp;
    }

    // Test control functions
    function setJackpotAmount(uint256 amount) external {
        jackpotAmount = amount;
        // When setting jackpot amount, transfer tokens to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    // Combined function to end round and set winner
    function endRoundWithWinner(address winner) external {
        _advanceRound();

        if (winner != address(0)) {
            _users[winner].winningsClaimable += jackpotAmount;
        }

        // Reset all participants' tickets and active status
        for (uint256 i = 0; i < _roundParticipants.length; i++) {
            address participant = _roundParticipants[i];
            _users[participant].ticketsPurchasedTotalBps = 0;
            _users[participant].active = false;
        }
        delete _roundParticipants;
    }

    function usersInfo(address user) external view override returns (User memory) {
        return _users[user];
    }

    function purchaseTickets(address, uint256 value, address recipient) external override {
        require(value >= ticketPrice, "Value too low");
        uint256 ticketsBps = (value * (10000 - feeBps)) / ticketPrice;

        User storage user = _users[recipient];
        user.ticketsPurchasedTotalBps += ticketsBps;
        user.active = true;
        _roundParticipants.push(recipient);

        // Transfer tokens from sender to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), value);
    }

    function withdrawWinnings() external override {
        User storage user = _users[msg.sender];
        require(user.winningsClaimable > 0, "No winnings to claim");

        uint256 amount = user.winningsClaimable;
        user.winningsClaimable = 0;

        // Transfer the winnings to the winner
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function withdrawReferralFees() external override {
        // Mock implementation - no referral fees in this mock
    }

    function _advanceRound() internal {
        lastJackpotEndTime = block.timestamp + roundDurationInSeconds;
    }
}
