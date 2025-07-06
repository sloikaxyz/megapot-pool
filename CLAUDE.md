# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JackpotPool is a Solidity smart contract that enables pooled participation in lottery/jackpot systems on the blockchain. Participants can pool funds together to purchase lottery tickets as a group, and winnings are distributed proportionally based on each participant's contribution.

## Commands

### Build and Compile
```bash
forge build                    # Compile all contracts
forge build --optimize         # Build with optimizer (20,000 runs configured)
forge clean                    # Clean build artifacts
```

### Testing
```bash
forge test                     # Run all tests
forge test -vv                 # Run tests with medium verbosity
forge test -vvv                # Run tests with high verbosity
forge test -vvvv               # Run tests with traces (for debugging)

# Run specific tests
forge test --match-test test_PurchaseOneTicket
forge test --match-test "test_Pool*"              # Pattern matching
forge test --match-contract JackpotPoolTest       # Test specific contract

# Advanced testing
forge test --gas-report        # Show gas usage
forge coverage                 # Generate coverage report
forge test --debug test_Name   # Debug specific test
```

### Code Quality
```bash
forge fmt                      # Format all Solidity files
forge fmt --check             # Check formatting without modifying
forge snapshot                # Generate gas snapshots
```

### Local Development
```bash
anvil                         # Start local blockchain
cast <subcommand>            # Interact with deployed contracts
```

## Architecture

### Contract Structure
```
src/
├── JackpotPool.sol              # Main pooling contract
├── JackpotPoolFactory.sol       # Factory for creating pool instances
└── interfaces/
    ├── IBaseJackpotPlay.sol     # Interface for external jackpot contracts
    └── IJackpotPoolFactory.sol  # Interface for the factory contract

test/
├── JackpotPool.t.sol            # Main test suite
├── JackpotPoolFactory.t.sol     # Factory test suite
└── mocks/
    ├── MockJackpot.sol          # Mock jackpot contract for testing
    ├── MockJackpotSecondary.sol # Secondary mock for multi-jackpot testing
    └── MockToken.sol            # Mock ERC20 token for testing
```

### Key Components

**JackpotPool Contract**:
- Manages pooled lottery participation
- Tracks participant contributions per round
- Automatically withdraws and distributes winnings
- Supports referral system pass-through
- Uses EnumerableMap for efficient winnings tracking
- Prevents double-withdrawals through payout tracking
- Stores the pool owner (creator) as an immutable public variable

**JackpotPoolFactory Contract**:
- Allows users to create their own pool instances
- Uses CREATE2 for deterministic pool addresses
- Combines jackpot, owner, and salt for unique deployment addresses
- Non-upgradeable pool instances (security by design)
- Emits events for pool creation tracking

**Contract Flow**:

*Pool Creation*:
1. User calls `factory.createPool(jackpotAddress, salt)` to create a new pool
2. Factory deploys a new JackpotPool instance using CREATE2
3. Pool stores the creator as the `owner` and initializes with the specified jackpot

*Pool Operation*:
1. Participants call `purchaseTickets()` to buy tickets through the pool
2. Pool tracks contributions in basis points (accounting for fees)
3. After round ends, anyone can call `withdrawWinnings()` 
4. Pool withdraws total winnings from jackpot contract
5. Participants call `claimWinnings()` to receive their proportional share

### State Management
- Pool owner (creator) stored as immutable public variable
- Current round tracking
- Participant ticket purchases mapped by round and address
- Winnings tracking using EnumerableMap
- Payout history to prevent double claims

### Testing Approach

Tests follow the pattern `test_<ScenarioDescription>` and cover:
- Single/multiple ticket purchases
- Winning distributions (even/uneven splits)
- Multiple rounds and participants
- Edge cases (double withdrawals, third-party recipients)
- Event emissions
- Factory functionality (deterministic deployment, multiple pools, address prediction)
- Pool independence and creator tracking

Test utilities use Foundry's vm cheatcodes:
- `vm.prank()` / `vm.startPrank()` for impersonation
- `vm.expectEmit()` for event testing
- Standard assertions with `assertEq()`

### Factory Usage Patterns

**Creating a Pool**:
```solidity
// Deploy factory (once)
JackpotPoolFactory factory = new JackpotPoolFactory();

// Create a pool for a specific jackpot
bytes32 salt = keccak256("my_unique_salt");
address poolAddress = factory.createPool(jackpotAddress, salt);
```

**Predicting Pool Address**:
```solidity
// Get pool address before deployment
address predictedAddress = factory.getPoolAddress(jackpotAddress, msg.sender, salt);
```

**Deterministic Deployment**:
- Pool addresses are deterministic based on: jackpot address + owner address + salt
- Same owner can create multiple pools for the same jackpot using different salts
- Different owners can use the same salt for the same jackpot (addresses will differ)
- Pool addresses are predictable and can be computed off-chain

### Development Notes

**Security Considerations**:
- Uses SafeERC20 for all token transfers
- Validates ticket purchase amounts (non-zero)
- Verifies expected vs actual winnings on withdrawal
- Tracks payouts to prevent double-withdrawals

**Gas Optimization**:
- Optimizer runs: 20,000 (optimized for deployment)
- Efficient storage patterns with mappings
- EnumerableMap for scalable winnings iteration

**Events Emitted**:
- `ParticipantTicketPurchase`: When tickets are purchased
- `PoolWithdrawWinnings`: When pool withdraws from jackpot
- `ParticipantClaimWinnings`: When participant claims their share

**Current Development Focus** (based on recent commits):
- Referrer field tracking in events
- Enhanced withdrawal verification
- Round synchronization improvements
- Proper fee tracking in basis points