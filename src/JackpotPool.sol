// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBaseJackpotPlay} from "./interfaces/IBaseJackpotPlay.sol";

contract JackpotPool {
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------------- */
    /*                                 EVENTS                                   */
    /* -------------------------------------------------------------------------- */
    /// @dev emitted when a participant purchases tickets
    event ParticipantTicketPurchase(
        address indexed participant, uint256 indexed round, uint256 ticketsPurchasedTotalBps, address indexed referrer
    );

    /// @dev emitted when a participant withdraws their winnings
    event ParticipantWinWithdrawal(address indexed participant, uint256 indexed round, uint256 payout);

    /// @dev emitted when the pool withdraws winnings from the jackpot
    event PoolWinWithdrawal(uint256 indexed round, uint256 amount);

    /* -------------------------------------------------------------------------- */
    /*                                 STATE VARIABLES                            */
    /* -------------------------------------------------------------------------- */
    /// @dev jackpot contract
    IBaseJackpotPlay public immutable jackpot;

    /// @dev jackpot token
    IERC20 private immutable jackpotToken;

    /// @dev latest round this pool has participated in.
    /// IMPORTANT: this value must be updated after withdrawing winnings from the Jackpot and before purchasing tickets.
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

        // withdraw any pending winnings before purchasing tickets
        _checkWinnings();
        // keep track of round changes
        _syncRound();

        uint256 ticketCount = value / ticketPrice;
        uint256 ticketsPurchasedBps = ticketCount * (10000 - jackpot.feeBps());

        // track tickets purchased in poolTickets, participantTickets
        poolTickets[currentRound] += ticketsPurchasedBps;
        participantTickets[recipient][currentRound] += ticketsPurchasedBps;

        // purchase tickets
        uint256 jackpotTokenBalanceBefore = poolTicketsPurchasedBps();
        jackpotToken.safeTransferFrom(msg.sender, address(this), value);
        jackpotToken.approve(address(jackpot), value);
        jackpot.purchaseTickets(referrer, value, address(this));
        require(
            poolTicketsPurchasedBps() == jackpotTokenBalanceBefore + ticketsPurchasedBps, "incorrect tickets purchased"
        );

        emit ParticipantTicketPurchase(recipient, currentRound, ticketsPurchasedBps, referrer);
    }

    function withdrawParticipantWinnings() external {
        _withdrawParticipantWinnings(msg.sender);
    }

    function withdrawParticipantWinnings(address participant_) external {
        _withdrawParticipantWinnings(participant_);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 INTERNAL FUNCTIONS                        */
    /* -------------------------------------------------------------------------- */
    /// @dev update `currentRound` to track participants' contributions
    function _syncRound() internal {
        uint256 lastJackpotEndTime = jackpot.lastJackpotEndTime();
        if (lastJackpotEndTime != currentRound) {
            currentRound = lastJackpotEndTime;
            // revert if attempting to update currentRound while there are pending winnings
            require(pendingPoolWinnings() == 0, "pool has pending winnings");
        }
    }

    function _checkWinnings() internal {
        uint256 pendingWinnings = pendingPoolWinnings();
        if (pendingWinnings > 0) {
            // record winnings for the current round
            winnings.set(currentRound, pendingWinnings);

            // get balance before withdrawal
            uint256 balanceBefore = jackpotToken.balanceOf(address(this));

            // withdraw winnings
            jackpot.withdrawWinnings();

            // verify the balance increased by the expected amount
            uint256 balanceAfter = jackpotToken.balanceOf(address(this));
            require(balanceAfter - balanceBefore == pendingWinnings, "incorrect winnings amount withdrawn");

            emit PoolWinWithdrawal(currentRound, pendingWinnings);
        }
    }

    function _withdrawParticipantWinnings(address participant_) internal {
        _checkWinnings();

        // iterate over all round the pool won in and withdraw due amount
        uint256 payout = 0;
        for (uint256 i = 0; i < winnings.length(); i++) {
            (uint256 round, uint256 poolWinnings) = winnings.at(i);
            uint256 ticketsPurchased = participantTickets[participant_][round];

            // skip if participant didn't purchase any tickets in the round
            if (ticketsPurchased == 0) continue;

            // calculate payout for this winning round
            uint256 roundPayout = (poolWinnings * ticketsPurchased) / poolTickets[round];

            // account for any amount already paid out to the participant
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
    /// Tickets purchased by this pool for the current round.
    function poolTicketsPurchasedBps() public view returns (uint256) {
        IBaseJackpotPlay.User memory userInfo = jackpot.usersInfo(address(this));
        return userInfo.active ? userInfo.ticketsPurchasedTotalBps : 0;
    }

    /// Winnings claimable *inside* BaseJackpot for this pool.
    function pendingPoolWinnings() public view returns (uint256) {
        IBaseJackpotPlay.User memory userInfo = jackpot.usersInfo(address(this));
        return userInfo.winningsClaimable;
    }
}
