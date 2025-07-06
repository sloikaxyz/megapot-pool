// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {JackpotPoolFactory} from "../src/JackpotPoolFactory.sol";
import {JackpotPool} from "../src/JackpotPool.sol";
import {MockJackpot} from "./mocks/MockJackpot.sol";
import {MockJackpotSecondary} from "./mocks/MockJackpotSecondary.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract JackpotPoolFactoryTest is Test {
    JackpotPoolFactory public factory;
    MockJackpot public jackpot;
    MockJackpotSecondary public jackpotSecondary;
    MockToken public token;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    uint256 public constant INITIAL_BALANCE = 10_000_000e6; // 10M tokens with 6 decimals
    uint256 public constant JACKPOT_AMOUNT = 1004466104303; // 1000 tokens with 6 decimals

    event PoolCreated(address indexed pool, address indexed jackpot, address indexed owner, bytes32 salt);

    function setUp() public {
        // Deploy contracts
        token = new MockToken();
        jackpot = new MockJackpot(address(token));
        jackpotSecondary = new MockJackpotSecondary(address(token));
        factory = new JackpotPoolFactory();

        // Fund test accounts
        token.transfer(alice, INITIAL_BALANCE);
        token.transfer(bob, INITIAL_BALANCE);
        token.transfer(charlie, INITIAL_BALANCE);

        // Set initial jackpot amounts
        token.approve(address(jackpot), JACKPOT_AMOUNT);
        jackpot.setJackpotAmount(JACKPOT_AMOUNT);

        token.approve(address(jackpotSecondary), JACKPOT_AMOUNT);
        jackpotSecondary.setJackpotAmount(JACKPOT_AMOUNT);
    }

    function test_CreatePool() public {
        bytes32 salt = keccak256("test_salt");

        // Get predicted address for event verification
        address predictedAddress = factory.getPoolAddress(address(jackpot), address(this), salt);

        vm.expectEmit(true, true, true, true);
        emit PoolCreated(predictedAddress, address(jackpot), address(this), salt);

        address poolAddress = factory.createPool(address(jackpot), salt);

        // Verify pool was created at predicted address
        assertEq(poolAddress, predictedAddress);

        // Verify pool has correct properties
        JackpotPool pool = JackpotPool(poolAddress);
        assertEq(pool.owner(), address(this));
        assertEq(address(pool.jackpot()), address(jackpot));
    }

    function test_CreatePoolWithDifferentOwners() public {
        bytes32 salt = keccak256("test_salt");

        // Alice creates a pool
        vm.prank(alice);
        address alicePoolAddress = factory.createPool(address(jackpot), salt);

        // Bob creates a pool with same salt (should work since different owner)
        vm.prank(bob);
        address bobPoolAddress = factory.createPool(address(jackpot), salt);

        // Verify pools are different
        assertTrue(alicePoolAddress != bobPoolAddress);

        // Verify owners are correct
        JackpotPool alicePool = JackpotPool(alicePoolAddress);
        JackpotPool bobPool = JackpotPool(bobPoolAddress);

        assertEq(alicePool.owner(), alice);
        assertEq(bobPool.owner(), bob);
    }

    function test_CreatePoolWithDifferentJackpots() public {
        bytes32 salt = keccak256("test_salt");

        // Create pool for first jackpot
        vm.prank(alice);
        address pool1Address = factory.createPool(address(jackpot), salt);

        // Create pool for second jackpot (same owner, same salt)
        vm.prank(alice);
        address pool2Address = factory.createPool(address(jackpotSecondary), salt);

        // Verify pools are different
        assertTrue(pool1Address != pool2Address);

        // Verify jackpots are correct
        JackpotPool pool1 = JackpotPool(pool1Address);
        JackpotPool pool2 = JackpotPool(pool2Address);

        assertEq(address(pool1.jackpot()), address(jackpot));
        assertEq(address(pool2.jackpot()), address(jackpotSecondary));
    }

    function test_CreatePoolWithDifferentSalts() public {
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        // Create two pools with different salts
        vm.prank(alice);
        address pool1Address = factory.createPool(address(jackpot), salt1);

        vm.prank(alice);
        address pool2Address = factory.createPool(address(jackpot), salt2);

        // Verify pools are different
        assertTrue(pool1Address != pool2Address);

        // Verify both pools have the same owner and jackpot
        JackpotPool pool1 = JackpotPool(pool1Address);
        JackpotPool pool2 = JackpotPool(pool2Address);

        assertEq(pool1.owner(), alice);
        assertEq(pool2.owner(), alice);
        assertEq(address(pool1.jackpot()), address(jackpot));
        assertEq(address(pool2.jackpot()), address(jackpot));
    }

    function test_GetPoolAddress() public {
        bytes32 salt = keccak256("test_salt");

        // Get predicted address
        address predictedAddress = factory.getPoolAddress(address(jackpot), alice, salt);

        // Create pool
        vm.prank(alice);
        address actualAddress = factory.createPool(address(jackpot), salt);

        // Verify addresses match
        assertEq(predictedAddress, actualAddress);
    }

    function test_GetPoolAddressWithDifferentParameters() public {
        bytes32 salt = keccak256("test_salt");

        // Get predicted addresses with different parameters
        address addr1 = factory.getPoolAddress(address(jackpot), alice, salt);
        address addr2 = factory.getPoolAddress(address(jackpot), bob, salt);
        address addr3 = factory.getPoolAddress(address(jackpotSecondary), alice, salt);
        address addr4 = factory.getPoolAddress(address(jackpot), alice, keccak256("different_salt"));

        // All addresses should be different
        assertTrue(addr1 != addr2);
        assertTrue(addr1 != addr3);
        assertTrue(addr1 != addr4);
        assertTrue(addr2 != addr3);
        assertTrue(addr2 != addr4);
        assertTrue(addr3 != addr4);
    }

    function test_CreatedPoolFunctionality() public {
        bytes32 salt = keccak256("test_salt");

        // Alice creates a pool
        vm.prank(alice);
        address poolAddress = factory.createPool(address(jackpot), salt);

        JackpotPool pool = JackpotPool(poolAddress);

        // Test that the pool works correctly
        uint256 purchaseAmount = jackpot.ticketPrice();

        // Fund Alice and approve the pool
        vm.startPrank(alice);
        token.approve(address(pool), purchaseAmount);

        // Purchase tickets through the pool
        pool.purchaseTickets(address(0), purchaseAmount, alice);

        // Verify tickets were purchased
        assertTrue(pool.poolTicketsPurchasedBps() > 0);

        vm.stopPrank();
    }

    function test_MultiplePoolsIndependentOperation() public {
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        // Alice creates two pools
        vm.prank(alice);
        address pool1Address = factory.createPool(address(jackpot), salt1);

        vm.prank(alice);
        address pool2Address = factory.createPool(address(jackpot), salt2);

        JackpotPool pool1 = JackpotPool(pool1Address);
        JackpotPool pool2 = JackpotPool(pool2Address);

        uint256 purchaseAmount = jackpot.ticketPrice();

        // Alice purchases tickets in pool1
        vm.startPrank(alice);
        token.approve(address(pool1), purchaseAmount);
        pool1.purchaseTickets(address(0), purchaseAmount, alice);
        vm.stopPrank();

        // Bob purchases tickets in pool2
        vm.startPrank(bob);
        token.approve(address(pool2), purchaseAmount);
        pool2.purchaseTickets(address(0), purchaseAmount, bob);
        vm.stopPrank();

        // Verify pools operate independently
        assertTrue(pool1.poolTicketsPurchasedBps() > 0);
        assertTrue(pool2.poolTicketsPurchasedBps() > 0);

        // Verify the pools don't interfere with each other
        assertEq(pool1.poolTicketsPurchasedBps(), pool2.poolTicketsPurchasedBps());
    }

    function test_RevertOnSameParameters() public {
        bytes32 salt = keccak256("test_salt");

        // Create first pool
        vm.prank(alice);
        factory.createPool(address(jackpot), salt);

        // Try to create second pool with same parameters - should revert
        vm.prank(alice);
        vm.expectRevert();
        factory.createPool(address(jackpot), salt);
    }

    function test_EventEmission() public {
        bytes32 salt = keccak256("test_salt");

        // Get predicted address for event verification
        address predictedAddress = factory.getPoolAddress(address(jackpot), alice, salt);

        vm.expectEmit(true, true, true, true);
        emit PoolCreated(predictedAddress, address(jackpot), alice, salt);

        vm.prank(alice);
        factory.createPool(address(jackpot), salt);
    }
}
