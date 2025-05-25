// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {JackpotPool} from "../src/JackpotPool.sol";
import {MockJackpot} from "./mocks/MockJackpot.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract JackpotPoolTest is Test {
    JackpotPool public pool;
    MockJackpot public jackpot;
    MockToken public token;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    uint256 public constant TICKET_PRICE = 1e6; // 1 token with 6 decimals
    uint256 public constant INITIAL_BALANCE = 10_000_000e6; // 1M tokens with 6 decimals
    uint256 public constant JACKPOT_AMOUNT = 1004466104303; // 1000 tokens with 6 decimals

    event ParticipantTicketPurchase(
        address indexed participant, uint256 indexed round, uint256 ticketsPurchasedTotalBps
    );
    event ParticipantWinWithdrawal(address indexed participant, uint256 indexed round, uint256 payout);
    event PoolWinWithdrawal(uint256 indexed round, uint256 amount);

    function setUp() public {
        // Deploy contracts
        token = new MockToken();
        jackpot = new MockJackpot(address(token));
        pool = new JackpotPool(address(jackpot));

        // Fund test accounts
        token.transfer(alice, INITIAL_BALANCE);
        token.transfer(bob, INITIAL_BALANCE);
        token.transfer(charlie, INITIAL_BALANCE);

        // Set initial jackpot amount
        token.approve(address(jackpot), JACKPOT_AMOUNT);
        jackpot.setJackpotAmount(JACKPOT_AMOUNT);
    }

    function test_PurchaseOneTicket() public {
        uint256 purchaseAmount = TICKET_PRICE;
        uint256 currentRound = jackpot.lastJackpotEndTime();

        vm.startPrank(alice);
        token.approve(address(pool), purchaseAmount);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(alice, currentRound, 9500); // 1 ticket * (10000 - 500) bps
        pool.purchaseTickets(address(0), purchaseAmount, alice);
        vm.stopPrank();

        // Verify tickets were purchased
        assertEq(pool.poolTicketsPurchasedBps(), 9500); // 1 ticket * (10000 - 500) bps
        assertEq(jackpot.usersInfo(address(pool)).ticketsPurchasedTotalBps, 9500);
    }

    function test_PurchaseTenTickets() public {
        uint256 purchaseAmount = 10 * TICKET_PRICE;
        uint256 currentRound = jackpot.lastJackpotEndTime();

        vm.startPrank(alice);
        token.approve(address(pool), purchaseAmount);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(alice, currentRound, 95000); // 10 tickets * (10000 - 500) bps
        pool.purchaseTickets(address(0), purchaseAmount, alice);
        vm.stopPrank();

        // Verify tickets were purchased
        assertEq(pool.poolTicketsPurchasedBps(), 95000); // 10 tickets * (10000 - 500) bps
        assertEq(jackpot.usersInfo(address(pool)).ticketsPurchasedTotalBps, 95000);
    }

    function test_PoolWinsRound() public {
        // Alice buys tickets through the pool
        uint256 aliceTickets = 10 * TICKET_PRICE;
        uint256 currentRound = jackpot.lastJackpotEndTime();

        vm.startPrank(alice);
        token.approve(address(pool), aliceTickets);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(alice, currentRound, 95000); // 10 tickets * (10000 - 500) bps
        pool.purchaseTickets(address(0), aliceTickets, alice);
        vm.stopPrank();

        // Set pool as winner and end round
        jackpot.endRoundWithWinner(address(pool));

        // Alice withdraws winnings
        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit PoolWinWithdrawal(currentRound, JACKPOT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ParticipantWinWithdrawal(alice, currentRound, JACKPOT_AMOUNT);

        pool.withdrawParticipantWinnings();
        vm.stopPrank();

        // Verify Alice received full jackpot (since she was the only participant)
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - aliceTickets + JACKPOT_AMOUNT);
    }

    function test_PoolLosesRound() public {
        // Alice buys tickets through the pool
        uint256 aliceTickets = 10 * TICKET_PRICE;
        vm.startPrank(alice);
        token.approve(address(pool), aliceTickets);
        pool.purchaseTickets(address(0), aliceTickets, alice);
        vm.stopPrank();

        // Set external winner and end round
        jackpot.endRoundWithWinner(charlie);

        // Alice tries to withdraw winnings
        vm.prank(alice);
        pool.withdrawParticipantWinnings();

        // Verify Alice received nothing (lost the round)
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - aliceTickets);
    }

    function test_ThirdPartyWinsWithPoolParticipants() public {
        // Alice and Bob buy tickets through the pool
        uint256 aliceTickets = 10 * TICKET_PRICE;
        uint256 bobTickets = 20 * TICKET_PRICE;

        vm.startPrank(alice);
        token.approve(address(pool), aliceTickets);
        pool.purchaseTickets(address(0), aliceTickets, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(pool), bobTickets);
        pool.purchaseTickets(address(0), bobTickets, bob);
        vm.stopPrank();

        // Charlie buys tickets directly from jackpot
        uint256 charlieTickets = 30 * TICKET_PRICE;
        vm.startPrank(charlie);
        token.approve(address(jackpot), charlieTickets);
        jackpot.purchaseTickets(address(0), charlieTickets, charlie);
        vm.stopPrank();

        // Set Charlie as winner and end round
        jackpot.endRoundWithWinner(charlie);

        // Alice and Bob try to withdraw winnings
        vm.prank(alice);
        pool.withdrawParticipantWinnings();
        vm.prank(bob);
        pool.withdrawParticipantWinnings();

        // Verify Alice and Bob received nothing (lost to Charlie)
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - aliceTickets);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - bobTickets);
    }

    function test_MultipleRounds() public {
        // Round 1: Pool wins
        uint256 aliceTickets = 10 * TICKET_PRICE;
        uint256 round1 = jackpot.lastJackpotEndTime();

        vm.startPrank(alice);
        token.approve(address(pool), aliceTickets);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(alice, round1, 95000); // 10 tickets * (10000 - 500) bps
        pool.purchaseTickets(address(0), aliceTickets, alice);
        vm.stopPrank();

        jackpot.endRoundWithWinner(address(pool));

        // Round 2: Pool loses
        uint256 bobTickets = 20 * TICKET_PRICE;
        uint256 round2 = jackpot.lastJackpotEndTime();

        vm.startPrank(bob);
        token.approve(address(pool), bobTickets);

        // Expect the pool to withdraw winnings from the first round before purchasing tickets in the second round
        vm.expectEmit(true, true, false, true);
        emit PoolWinWithdrawal(round1, JACKPOT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(bob, round2, 190000); // 20 tickets * (10000 - 500) bps
        pool.purchaseTickets(address(0), bobTickets, bob);
        vm.stopPrank();

        // Need to fund the jackpot for the second round
        token.approve(address(jackpot), JACKPOT_AMOUNT);
        jackpot.setJackpotAmount(JACKPOT_AMOUNT);

        jackpot.endRoundWithWinner(charlie);

        // Alice withdraws winnings from the first round
        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit ParticipantWinWithdrawal(alice, round1, JACKPOT_AMOUNT);

        pool.withdrawParticipantWinnings();
        vm.stopPrank();

        // Bob withdraws no winnings
        vm.startPrank(bob);
        pool.withdrawParticipantWinnings(); // No events expected since Bob didn't win anything
        vm.stopPrank();

        // Verify Alice received winnings from round 1 only
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - aliceTickets + JACKPOT_AMOUNT);
        // Verify Bob received nothing (lost in round 2)
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - bobTickets);
    }

    function test_PoolWinsAndDistributesAfterInactivity() public {
        // Round 1: Pool wins with Alice and Bob participating
        uint256 aliceTickets = 1 * TICKET_PRICE;
        uint256 bobTickets = 2 * TICKET_PRICE;

        vm.startPrank(alice);
        token.approve(address(pool), aliceTickets);
        pool.purchaseTickets(address(0), aliceTickets, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(pool), bobTickets);
        pool.purchaseTickets(address(0), bobTickets, bob);
        vm.stopPrank();

        // Pool wins round 1
        jackpot.endRoundWithWinner(address(pool));

        // Store expected winnings from round 1
        uint256 aliceExpectedWinnings = JACKPOT_AMOUNT / 3; // 1/3 of jackpot
        uint256 bobExpectedWinnings = (JACKPOT_AMOUNT * 2) / 3; // 2/3 of jackpot

        // Round 2: No winner, pool is inactive
        // Need to fund the jackpot for the second round
        token.approve(address(jackpot), JACKPOT_AMOUNT);
        jackpot.setJackpotAmount(JACKPOT_AMOUNT);

        // Charlie participates directly in jackpot
        vm.startPrank(charlie);
        token.approve(address(jackpot), TICKET_PRICE);
        jackpot.purchaseTickets(address(0), TICKET_PRICE, charlie);
        vm.stopPrank();

        jackpot.endRoundWithWinner(address(0));

        // Round 3: Charlie wins, pool is still inactive
        // Need to fund the jackpot for the third round
        token.approve(address(jackpot), JACKPOT_AMOUNT);
        jackpot.setJackpotAmount(JACKPOT_AMOUNT);

        // Charlie participates again
        vm.startPrank(charlie);
        token.approve(address(jackpot), TICKET_PRICE);
        jackpot.purchaseTickets(address(0), TICKET_PRICE, charlie);
        vm.stopPrank();

        jackpot.endRoundWithWinner(charlie);

        // Now Alice and Bob withdraw their winnings from round 1
        vm.prank(alice);
        pool.withdrawParticipantWinnings();
        vm.prank(bob);
        pool.withdrawParticipantWinnings();

        // Verify Alice and Bob received correct winnings from round 1
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - aliceTickets + aliceExpectedWinnings);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - bobTickets + bobExpectedWinnings);
    }

    function test_PoolWinsRoundEvenSplit() public {
        // Alice and Bob buy equal amounts of tickets through the pool
        uint256 aliceTickets = 10 * TICKET_PRICE;
        uint256 bobTickets = 10 * TICKET_PRICE;
        uint256 currentRound = jackpot.lastJackpotEndTime();
        uint256 expectedWinnings = JACKPOT_AMOUNT / 2;

        vm.startPrank(alice);
        token.approve(address(pool), aliceTickets);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(alice, currentRound, 95000); // 10 tickets * (10000 - 500) bps
        pool.purchaseTickets(address(0), aliceTickets, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(pool), bobTickets);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(bob, currentRound, 95000); // 10 tickets * (10000 - 500) bps
        pool.purchaseTickets(address(0), bobTickets, bob);
        vm.stopPrank();

        // Set pool as winner and end round
        jackpot.endRoundWithWinner(address(pool));

        // Both participants withdraw winnings
        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit PoolWinWithdrawal(currentRound, JACKPOT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ParticipantWinWithdrawal(alice, currentRound, expectedWinnings);

        pool.withdrawParticipantWinnings();
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit ParticipantWinWithdrawal(bob, currentRound, expectedWinnings);
        pool.withdrawParticipantWinnings();
        vm.stopPrank();

        // Verify Alice and Bob each received half of the jackpot (since they had equal tickets)
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - aliceTickets + expectedWinnings);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - bobTickets + expectedWinnings);
    }

    function test_PoolWinsRoundUnevenSplit() public {
        // Alice buys 1 ticket and Bob buys 2 tickets through the pool
        uint256 aliceTickets = 1 * TICKET_PRICE;
        uint256 bobTickets = 2 * TICKET_PRICE;
        uint256 currentRound = jackpot.lastJackpotEndTime();
        uint256 aliceExpectedWinnings = JACKPOT_AMOUNT / 3;
        uint256 bobExpectedWinnings = (JACKPOT_AMOUNT * 2) / 3;

        vm.startPrank(alice);
        token.approve(address(pool), aliceTickets);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(alice, currentRound, 9500); // 1 ticket * (10000 - 500) bps
        pool.purchaseTickets(address(0), aliceTickets, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(pool), bobTickets);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(bob, currentRound, 19000); // 2 tickets * (10000 - 500) bps
        pool.purchaseTickets(address(0), bobTickets, bob);
        vm.stopPrank();

        // Set pool as winner and end round
        jackpot.endRoundWithWinner(address(pool));

        // Both participants withdraw winnings
        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit PoolWinWithdrawal(currentRound, JACKPOT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ParticipantWinWithdrawal(alice, currentRound, aliceExpectedWinnings);

        pool.withdrawParticipantWinnings();
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit ParticipantWinWithdrawal(bob, currentRound, bobExpectedWinnings);
        pool.withdrawParticipantWinnings();
        vm.stopPrank();

        // Verify proportional winnings distribution
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - aliceTickets + aliceExpectedWinnings);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - bobTickets + bobExpectedWinnings);
    }

    function test_PoolWinsRoundUnevenSplitThreeParticipants() public {
        // Alice buys 1 ticket, Bob buys 2 tickets, and Charlie buys 3 tickets through the pool
        uint256 aliceTickets = 1 * TICKET_PRICE;
        uint256 bobTickets = 2 * TICKET_PRICE;
        uint256 charlieTickets = 3 * TICKET_PRICE;
        uint256 currentRound = jackpot.lastJackpotEndTime();
        uint256 aliceExpectedWinnings = JACKPOT_AMOUNT / 6;
        uint256 bobExpectedWinnings = JACKPOT_AMOUNT / 3;
        uint256 charlieExpectedWinnings = JACKPOT_AMOUNT / 2;

        vm.startPrank(alice);
        token.approve(address(pool), aliceTickets);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(alice, currentRound, 9500); // 1 ticket * (10000 - 500) bps
        pool.purchaseTickets(address(0), aliceTickets, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(pool), bobTickets);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(bob, currentRound, 19000); // 2 tickets * (10000 - 500) bps
        pool.purchaseTickets(address(0), bobTickets, bob);
        vm.stopPrank();

        vm.startPrank(charlie);
        token.approve(address(pool), charlieTickets);

        vm.expectEmit(true, true, false, true);
        emit ParticipantTicketPurchase(charlie, currentRound, 28500); // 3 tickets * (10000 - 500) bps
        pool.purchaseTickets(address(0), charlieTickets, charlie);
        vm.stopPrank();

        // Set pool as winner and end round
        jackpot.endRoundWithWinner(address(pool));

        // All participants withdraw winnings
        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit PoolWinWithdrawal(currentRound, JACKPOT_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ParticipantWinWithdrawal(alice, currentRound, aliceExpectedWinnings);

        pool.withdrawParticipantWinnings();
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectEmit(true, true, false, true);
        emit ParticipantWinWithdrawal(bob, currentRound, bobExpectedWinnings);
        pool.withdrawParticipantWinnings();
        vm.stopPrank();

        vm.startPrank(charlie);
        vm.expectEmit(true, true, false, true);
        emit ParticipantWinWithdrawal(charlie, currentRound, charlieExpectedWinnings);
        pool.withdrawParticipantWinnings();
        vm.stopPrank();

        // Verify proportional winnings distribution
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - aliceTickets + aliceExpectedWinnings);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - bobTickets + bobExpectedWinnings);
        assertEq(token.balanceOf(charlie), INITIAL_BALANCE - charlieTickets + charlieExpectedWinnings);
    }
}
