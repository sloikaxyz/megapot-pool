// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

interface IBaseJackpotPlay {
    // Structs
    struct User {
        /// Total tickets purchased by the user for current jackpot, multiplied by 10000, resets each jackpot
        uint256 ticketsPurchasedTotalBps;
        /// Tracks the total win amount in token (how much the user can withdraw.)
        uint256 winningsClaimable;
        /// Whether or not the user is participating in the current jackpot
        bool active;
    }

    // JACKPOT VARIABLES
    /// token address
    function token() external view returns (address);
    /// price of a ticket in native token units
    function ticketPrice() external view returns (uint256);
    /// fee bps
    function feeBps() external view returns (uint256);
    /// round duration in seconds
    function roundDurationInSeconds() external view returns (uint256);
    /// timestamp of the last jackpot end time
    function lastJackpotEndTime() external view returns (uint256);
    /// user info, mapping of user address to user struct
    function usersInfo(address user) external view returns (User memory);

    // PLAYER FUNCTIONS
    /// purchase tickets for the current jackpot
    function purchaseTickets(address referrer, uint256 value, address recipient) external;
    /// withdraw caller's winnings
    function withdrawWinnings() external;

    // REFERRAL FUNCTIONS
    /// withdraw caller's referral fees
    function withdrawReferralFees() external;
}
