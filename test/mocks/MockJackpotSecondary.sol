// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBaseJackpotPlay} from "../../src/interfaces/IBaseJackpotPlay.sol";

contract MockJackpotSecondary is IBaseJackpotPlay {
    using SafeERC20 for IERC20;

    address public immutable override token;
    uint256 public override ticketPrice = 2e6; // 2 tokens with 6 decimals (different from MockJackpot)
    uint256 public override feeBps = 300; // 3% fee (different from MockJackpot)
    uint256 public override roundDurationInSeconds = 2 days;
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

    function setTicketPrice(uint256 price) external {
        ticketPrice = price;
    }

    function setFee(uint256 fee) external {
        feeBps = fee;
    }

    function setRoundDuration(uint256 duration) external {
        roundDurationInSeconds = duration;
    }

    function simulateRoundEnd() external {
        lastJackpotEndTime = block.timestamp;
    }

    function setWinner(address winner) external {
        _users[winner].winningsClaimable = jackpotAmount;
        jackpotAmount = 0;
    }

    function setWinnerMultipleParticipants(address[] memory winners, uint256[] memory amounts) external {
        require(winners.length == amounts.length, "Arrays must have same length");
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < winners.length; i++) {
            _users[winners[i]].winningsClaimable = amounts[i];
            totalAmount += amounts[i];
        }
        require(totalAmount <= jackpotAmount, "Total winnings exceed jackpot amount");
        jackpotAmount -= totalAmount;
    }

    // IBaseJackpotPlay implementation
    function purchaseTickets(address, uint256 value, address recipient) external override {
        require(value > 0 && (value % ticketPrice == 0), "Invalid purchase amount");

        uint256 ticketCount = value / ticketPrice;
        uint256 ticketsPurchasedBps = ticketCount * (10000 - feeBps);

        _users[recipient].ticketsPurchasedTotalBps += ticketsPurchasedBps;
        _users[recipient].active = true;

        // Transfer tokens from sender to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), value);

        // Add to round participants if not already present
        bool isParticipant = false;
        for (uint256 i = 0; i < _roundParticipants.length; i++) {
            if (_roundParticipants[i] == recipient) {
                isParticipant = true;
                break;
            }
        }
        if (!isParticipant) {
            _roundParticipants.push(recipient);
        }
    }

    function withdrawWinnings() external override {
        uint256 winnings = _users[msg.sender].winningsClaimable;
        require(winnings > 0, "No winnings to withdraw");

        _users[msg.sender].winningsClaimable = 0;
        IERC20(token).safeTransfer(msg.sender, winnings);
    }

    function withdrawReferralFees() external override {
        // Not implemented for this mock
        revert("Not implemented");
    }

    function usersInfo(address user) external view override returns (User memory) {
        return _users[user];
    }
}
