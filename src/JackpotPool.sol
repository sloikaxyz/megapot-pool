// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBaseJackpotPlay} from "./interfaces/IBaseJackpotPlay.sol";

contract JackpotPool {
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using SafeERC20 for IERC20;

    /// @dev emitted when a participant withdraws their winnings
    event ParticipantWinWithdrawal(address indexed participant, uint256 indexed round, uint256 payout);

    /// @dev jackpot contract
    IBaseJackpotPlay public immutable jackpot;

    /// @dev jackpot token
    IERC20 private immutable jackpotToken;

    /// @dev latest round this pool has participated in
    uint256 private currentRound;
    /// @dev quantity of tickets purchased by the pool in a given round
    mapping(uint256 => uint256) private poolTickets;
    /// @dev quantity of tickets purchased by a participant in a given round
    mapping(address => mapping(uint256 => uint256)) private participantTickets;

    /// @dev winnings[round] = amount won by the pool in a given round
    EnumerableMap.UintToUintMap private winnings;
    /// @dev participantPayout[participant][round] = amount already paid out to the participant
    mapping(address => mapping(uint256 => uint256)) private participantPayout;

    constructor(address jackpot_) {
        jackpot = IBaseJackpotPlay(jackpot_);
        jackpotToken = IERC20(jackpot.token());
        currentRound = jackpot.lastJackpotEndTime();
    }

    function purchaseTickets(address referrer, uint256 value, address recipient) external {
        uint256 ticketPrice = jackpot.ticketPrice();
        require(value > 0 && (value % ticketPrice == 0), "invalid purchase amount");

        // keep track of round changes
        _syncRound();

        // track tickets purchased in poolTickets, participantTickets
        poolTickets[currentRound] += value;
        participantTickets[recipient][currentRound] += value;

        // purchase tickets
        jackpotToken.safeTransferFrom(msg.sender, address(this), value);
        jackpotToken.approve(address(jackpot), value);
        jackpot.purchaseTickets(referrer, value, address(this));

        // TODO: Verify we received the expected amount of userInfo.ticketsPurchasedTotalBps, I guess?
        // TODO: Emit an event, include recipient, round, value of tickets purchased
    }

    function withdrawParticipantWinnings() external {
        _withdrawParticipantWinnings(msg.sender);
    }

    function withdrawParticipantWinnings(address participant_) external {
        _withdrawParticipantWinnings(participant_);
    }

    /// @dev keep track of round changes and check for winnings if round has changed; updates `currentRound`
    function _syncRound() internal {
        uint256 lastJackpotEndTime = jackpot.lastJackpotEndTime();
        if (lastJackpotEndTime != currentRound) {
            _checkWinnings();
            currentRound = lastJackpotEndTime;
        }
    }

    function _checkWinnings() internal {
        uint256 pendingWinnings = pendingPoolWinnings();
        if (pendingWinnings > 0) {
            // record winnings for the current round
            winnings.set(currentRound, pendingWinnings);

            // TODO: Verify we received the correct amount by comparing the jackpot.token balance before and after the withdraw
            // TODO: Emit an event, include round, pendingWinnings
            jackpot.withdrawWinnings();
        }
    }

    function _withdrawParticipantWinnings(address participant_) internal {
        // TODO: Iterate over all round winnings and withdraw due amount.
        uint256 payout = 0;
        for (uint256 i = 0; i < winnings.length(); i++) {
            (uint256 round, uint256 poolWinnings) = winnings.at(i);
            uint256 ticketsPurchased = participantTickets[participant_][round];

            // skip if participant didn't purchase any tickets in the round
            if (ticketsPurchased == 0) continue;

            // calculate payout for this winning round
            uint256 roundPayout = (poolWinnings * ticketsPurchased) / poolTickets[round];

            // account for any amount already paid out to the participant
            // TODO: is there a better way to do this?
            uint256 outstandingPayout = roundPayout - participantPayout[participant_][round];

            // skip if no payout is due
            if (outstandingPayout == 0) continue;

            // track payout in participantPayout
            participantPayout[participant_][round] += outstandingPayout;

            // add outstanding payout for this round to the total payout
            payout += outstandingPayout;
            // emit an accounting event to track payouts by recipient
            emit ParticipantWinWithdrawal(participant_, round, outstandingPayout);
        }

        // send payout to the participant
        IERC20(jackpot.token()).safeTransfer(participant_, payout);
    }

    /* -------------------------------------------------------------------------- */
    /*                             External view helpers                          */
    /* -------------------------------------------------------------------------- */
    /// Winnings claimable *inside* BaseJackpot for this pool.
    function pendingPoolWinnings() public view returns (uint256) {
        IBaseJackpotPlay.User memory userInfo = jackpot.usersInfo(address(this));
        return userInfo.winningsClaimable;
    }
}
