# Account Abstraction: Ethereum & zkSync

A side-by-side implementation of account abstraction for both Ethereum (ERC-4337) and zkSync Era. Built this to understand the differences between the two approaches and how to work with each.

Both implementations are minimal but functional - they handle signature validation, nonce management, and transaction execution. The code is intentionally simple to make it easier to see what's happening under the hood.

## Why Account Abstraction?

Regular Ethereum accounts (EOAs) are pretty limited. You need ETH for gas, can't do multi-sig easily, and there's no way to add custom logic. Account abstraction fixes this by making accounts themselves smart contracts.

The catch? Ethereum and zkSync do it completely differently:

- **Ethereum**: ERC-4337 uses an EntryPoint contract. You create UserOperations (not transactions), bundlers pick them up, and EntryPoint handles validation/execution.
- **zkSync**: Native account abstraction. The bootloader (not a real contract, but acts like one) calls your account contract directly. No bundlers needed.

I wanted to see both in action, so here we are. The implementations are intentionally minimal - just enough to understand how each works.

## Architecture

### Ethereum Implementation (`MinimalAccount`)

Implements the `IAccount` interface from ERC-4337:

```
User → Signs UserOperation → Bundler → EntryPoint → MinimalAccount.validateUserOp()
                                                      ↓
                                              MinimalAccount.execute()
```

**Key Components:**
- `EntryPoint`: Singleton contract that validates and executes UserOperations
- `MinimalAccount`: Smart contract wallet that validates signatures and executes calls
- Uses `PackedUserOperation` format for gas efficiency

**Flow:**
1. User signs a UserOperation (not a transaction)
2. Bundler picks it up and calls `EntryPoint.handleOps()`
3. EntryPoint calls `validateUserOp()` to check signature and nonce
4. EntryPoint calls `execute()` to perform the actual operation
5. EntryPoint handles gas payment and refunds

### zkSync Implementation (`ZkMinimalAccount`)

Implements the `IAccount` interface from zkSync's system contracts:

```
User → Signs Transaction → zkSync API → Bootloader → ZkMinimalAccount.validateTransaction()
                                                       ↓
                                               ZkMinimalAccount.executeTransaction()
```

**Key Components:**
- `Bootloader`: Ephemeral contract (not deployed) that orchestrates transactions
- `ZkMinimalAccount`: Smart contract wallet that validates and executes
- Uses `Transaction` struct format specific to zkSync
- Direct system contract calls (e.g., `NONCE_HOLDER_SYSTEM_CONTRACT`)

**Flow:**
1. User signs a Transaction struct
2. zkSync API validates the transaction
3. Bootloader calls `validateTransaction()` to check signature and increment nonce
4. Bootloader calls `payForTransaction()` to handle gas payment
5. Bootloader calls `executeTransaction()` to perform the operation

## Key Differences

| Feature | Ethereum (ERC-4337) | zkSync |
|---------|---------------------|--------|
| Entry Point | EntryPoint contract | Bootloader (ephemeral) |
| Operation Format | PackedUserOperation | Transaction struct |
| Nonce Management | EntryPoint.getNonce() | NONCE_HOLDER_SYSTEM_CONTRACT |
| Validation | validateUserOp() | validateTransaction() |
| Execution | execute() | executeTransaction() |
| Gas Payment | _payPrefund() | payForTransaction() |
| System Calls | Standard EVM calls | SystemContractsCaller |

The biggest practical difference: on Ethereum you need bundlers to submit UserOperations, on zkSync the API handles it natively. Also, zkSync's system contracts are easier to work with once you get the hang of `SystemContractsCaller`.

## Project Structure

```
.
├── src/
│   ├── ethereum/
│   │   └── MinimalAccount.sol          # ERC-4337 implementation
│   └── zksync/
│       └── ZkMinimalAccount.sol        # zkSync native AA implementation
├── test/
│   ├── ethereum/
│   │   └── MinimalAccountTest.t.sol    # Tests for Ethereum version
│   └── zksync/
│       └── ZkMinimalAccountTest.t.sol # Tests for zkSync version
├── script/
│   ├── DeployMinimalAccount.s.sol      # Deployment script
│   ├── HelperConfig.s.sol              # Network configuration
│   └── SendPackedUserOp.s.sol          # UserOperation generation helper
└── foundry.toml                        # Foundry configuration
```

## Setup

### Prerequisites

- [Foundry](https://getfoundry.sh/) (for Ethereum)
- [Foundry zkSync](https://github.com/matter-labs/foundry-zksync) (for zkSync)
- Node.js (for zkSync local node)

### Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd account-abstraction-foundry

# Install dependencies
make install

# Or manually:
forge install foundry-rs/forge-std@v1.8.2 --no-commit
forge install openzeppelin/openzeppelin-contracts@v5.0.2 --no-commit
forge install eth-infinitism/account-abstraction@v0.7.0 --no-commit
forge install cyfrin/foundry-era-contracts@0.0.3 --no-commit
```

## Running Tests

### Ethereum Tests

```bash
# Run all Ethereum tests
forge test

# Run specific test
forge test --match-test testEntryPointCanExecute -vvv

# Run with gas reporting
forge test --gas-report
```

The Ethereum tests use Anvil (local EVM) and deploy a fresh EntryPoint contract for each test run.

### zkSync Tests

```bash
# Switch to zkSync Foundry
foundryup-zksync

# Run zkSync tests
forge test --zksync --system-mode=true

# Switch back to regular Foundry
foundryup
```

Or use the Makefile:

```bash
make zktest
```

**Important**: zkSync tests need `is-system = true` in `foundry.toml`. You'll get a warning about it being unknown, but ignore that - it's a zkSync-specific flag that the compiler backend understands. Without it, calls to system contracts like `NONCE_HOLDER_SYSTEM_CONTRACT` won't work.

## Local Development

### Ethereum (Anvil)

```bash
# Start Anvil
anvil

# Or with custom mnemonic
anvil -m 'test test test test test test test test test test test junk'
```

Anvil will deploy a fresh EntryPoint contract automatically via `HelperConfig`.

### zkSync Local Node

```bash
# Start zkSync local node
npx zksync-cli dev start

# Or use the Makefile
make zkanvil
```

## Deployment

### Ethereum Deployment

```bash
# Deploy to Anvil (local)
forge script script/DeployMinimalAccount.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to Sepolia
forge script script/DeployMinimalAccount.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify
```

The deployment script automatically detects the network and uses the appropriate EntryPoint address:
- **Anvil**: Deploys a new EntryPoint
- **Sepolia**: Uses the canonical EntryPoint at `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`

### zkSync Deployment

```bash
# Switch to zkSync Foundry
foundryup-zksync

# Build for zkSync
forge build --zksync

# Deploy (requires zkSync CLI setup)
yarn deploy
```

## How It Works

### Ethereum Flow

The flow is a bit indirect but that's by design:

1. Create a UserOperation (not a transaction) - see `SendPackedUserOp.generateSignedUserOperation()`
2. Get the nonce from EntryPoint: `EntryPoint.getNonce(account, 0)`
3. Sign the UserOperation hash (EIP-191)
4. Either send to a bundler or call `EntryPoint.handleOps()` yourself

The EntryPoint does validation first, then execution. If validation fails, you don't pay execution gas - nice optimization.

### zkSync Flow

More straightforward since it's native:

1. Build a `Transaction` struct (check the test file for an example)
2. Get nonce: `vm.getNonce(account)` works here
3. Sign the transaction hash (EIP-191)
4. Send to zkSync API - they handle the rest

The bootloader calls your contract in phases: validate, pay, execute. Each phase is a separate call.

### Key Implementation Details

**Ethereum:**
- Nonce is managed by EntryPoint (`getNonce()`)
- Gas is paid via `_payPrefund()` which transfers ETH to EntryPoint
- Validation happens before execution (saves gas on invalid ops)

**zkSync:**
- Nonce is managed by `NONCE_HOLDER_SYSTEM_CONTRACT` (system call)
- Gas is paid via `payForTransaction()` which transfers to bootloader
- Validation and execution are separate phases

## Common Issues

### "is-system config unknown" Warning

Yeah, you'll see this warning. It's because Foundry's config parser doesn't recognize `is-system` yet, but the zkSync compiler backend does. Just ignore it - your code will compile fine. You need this flag if your contract calls any system contracts (like `NONCE_HOLDER_SYSTEM_CONTRACT`).

### Nonce Mismatch

This one got me at first. EntryPoint has its own nonce system that's separate from regular transaction nonces.

**Ethereum**: Always use `EntryPoint.getNonce(account, 0)`. The `0` is the nonce key (lets you have parallel nonce sequences if you want). Don't use `vm.getNonce()` - that's for regular transactions.

**zkSync**: Use `vm.getNonce()` or call `NONCE_HOLDER_SYSTEM_CONTRACT` directly. The nonce system is simpler here.

### Signature Recovery Fails

Make sure you're signing the correct hash:
- **Ethereum**: `MessageHashUtils.toEthSignedMessageHash(userOpHash)`
- **zkSync**: `MessageHashUtils.toEthSignedMessageHash(transaction.encodeHash())`

## What's Tested

**Ethereum tests:**
- Direct execution (owner can call `execute()`)
- Access control (non-owner gets reverted)
- Signature recovery (can verify who signed)
- EntryPoint integration (full UserOperation flow)
- Validation logic (signature checks, nonce handling)

**zkSync tests:**
- Transaction execution
- Bootloader validation flow
- System contract calls (nonce increment)
- Balance checks before execution

The tests are pretty basic - they verify the core functionality works. Add more as needed for your use case.

## When to Use Which?

**Use Ethereum (ERC-4337) if:**
- You need to deploy on mainnet/L2s that support ERC-4337
- You want to use existing bundler infrastructure
- You're building something that needs to work across multiple chains

**Use zkSync if:**
- You're building specifically for zkSync Era
- You want native account abstraction (no bundlers)
- You need lower gas costs and faster finality

Both implementations follow similar patterns - validate signature, check nonce, execute. The main difference is who calls your contract and how.

## Resources

- [ERC-4337 Specification](https://eips.ethereum.org/EIPS/eip-4337)
- [zkSync Account Abstraction Docs](https://docs.zksync.io/build/developer-reference/account-abstraction)
- [Foundry Book](https://book.getfoundry.sh/)
- [Foundry zkSync](https://github.com/matter-labs/foundry-zksync)

## License

MIT
