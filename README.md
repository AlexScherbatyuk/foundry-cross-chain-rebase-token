# Cross-chain Rebase Token

A cross-chain rebase token protocol where users deposit ETH into a vault to mint RBT 1:1; balances grow linearly over time based on a per-user snapshot rate, and CCIP bridging burns/mints while preserving that rate across chains.

## Features

- **Dynamic Balance**: The `balanceOf` function is dynamic to show the increasing balance with time
- **Linear Growth**: Balance increases linearly with time
- **Action-based Minting**: Mint tokens to users every time they perform an action (minting, burning, transferring, or bridging)
- **Individual Interest Rates**: Each user gets an individually set interest rate based on the global interest rate at the time of deposit
- **Early Adopter Rewards**: Global interest rate can only decrease to incentivize/reward early adopters
- **Token Adoption**: Designed to increase token adoption

## How it works

- **Vault deposits and redemptions**: Users deposit native ETH into `Vault`, which mints `RebaseToken` 1:1 at the current global interest rate snapshot for that user. On redemption, the token is burned and ETH is returned.
- **Per-user interest snapshots**: On first mint (via deposit or inbound bridge), the user receives a personal interest rate equal to the then-current global rate. That personal rate stays fixed for that user and is used for all future accrual.
- **On-demand interest materialization**: Actual token supply growth is materialized on actions (mint, burn, transfer, bridge). Before each action, accrued interest since the last interaction is minted to the user via `_mintAccruedInterest`.
- **Cross-chain via CCIP**: When bridging, the source `RebaseTokenPool` burns tokens and forwards the sender’s personal interest rate to the destination pool, which mints the same amount to the receiver and sets their user rate to match.

### Interest math

- Balance is computed as: `balance = principal * (1e18 + userRatePerSecond * timeElapsed) / 1e18`.
- The initial global rate is `5e10` (≈ `5e-8` per second). The global rate can only decrease. New depositors inherit the current (potentially lower) rate.
- On transfers, if the recipient has a zero balance, the recipient inherits the sender’s user rate on first receipt.

## Contracts

- `src/RebaseToken.sol`: ERC20 with rebase logic, per-user interest snapshots, and `MINT_AND_BURN_ROLE` used by trusted actors (vault and pool).
- `src/Vault.sol`: Holds ETH. `deposit()` mints RBT 1:1 at the current global rate snapshot. `redeem(amount)` burns tokens and sends back ETH. Supports `type(uint256).max` to redeem full balance.
- `src/RebaseTokenPool.sol`: Chainlink CCIP-compatible `TokenPool` that customizes:
  - `lockOrBurn`: burns tokens and encodes the sender’s per-user rate into `destPoolData`.
  - `releaseOrMint`: decodes `destPoolData` and mints to the receiver with the same per-user rate.

## Deployed Contracts

### ZKsync
- **Rebase Token Address**: `0xCce3aa8C657ccC5B9Af3037C9dD2DFFFEABdE889`
- **Pool Address**: `0x68dd6a0195b2588e05C87Be1e2643137658c9D79`

### Sepolia
- **Rebase Token Address**: `0xd4Cfe90b37520B542ae259fcb522513c83A34ac8`
- **Pool Address**: `0xB8fBF532e20316372a355B6f70c53B2089dDb627`

## CCIP Transactions

- **Explored Hash**: `0x4a293190ac060bef8753298445367470e1a4a3481272d6f211a7f3bfc37d5bd0`

## Chainlink CCIP roles and setup

- **Token admin (CCIP Token Admin)**: Owns token ↔ pool configuration.
  1) Register admin via token owner: `RegistryModuleOwnerCustom.registerAdminViaOwner(token)`
  2) Accept admin role: `TokenAdminRegistry.acceptAdminRole(token)`
  3) Set the token's pool: `TokenAdminRegistry.setPool(token, pool)`

- **MINT_AND_BURN_ROLE on the token**: Granted to trusted actors that need to mint/burn:
  - `Vault` (mints on deposit; burns on redeem)
  - `RebaseTokenPool` (burns on source chain; mints on destination chain)

- **Router and RMN**: `RebaseTokenPool` takes CCIP `router` and `rmnProxy`. In tests/scripts we fetch them from `CCIPLocalSimulatorFork.getNetworkDetails(block.chainid)`. On real networks use production addresses from Chainlink docs.

- **Chain allowlisting**: Use `TokenPool.applyChainUpdates` to allow a remote chain, set the remote pool/token addresses, and configure rate limiters.

## Getting Started

### Prerequisites

- Foundry (forge/cast)
- RPC URLs for your target chains (e.g., Sepolia, Arbitrum Sepolia)
- LINK on source chain for CCIP fees

### Install dependencies

```bash
make install
```

Installs:
- OpenZeppelin Contracts v5.4.0
- Chainlink CCIP v2.17.0-ccip1.5.16
- chainlink-local v0.2.5-beta.0 (for `CCIPLocalSimulatorFork`)

### Run tests

```bash
forge test -vvv
```

### Local CCIP simulation (multi-fork)

- `test/CrossChain.t.sol` spins up Sepolia and Arbitrum Sepolia forks, deploys token, pool, vault, registers CCIP Token Admin, sets pool, configures lanes, then bridges tokens end-to-end.

## Deployment and configuration

Scripts use Foundry `forge script`.

### 1) Deploy token and pool

```bash
forge script script/Deployer.s.sol:TokenAndPoolDeployer \
  --rpc-url $RPC_URL \
  --broadcast
```

### 2) Grant token role to the pool

```bash
forge script script/Deployer.s.sol:SetPermissions \
  --sig "grantRole(address,address)" \
  <TOKEN_ADDRESS> <POOL_ADDRESS> \
  --rpc-url $RPC_URL \
  --broadcast
```

### 3) Register CCIP Token Admin and set pool

```bash
forge script script/Deployer.s.sol:SetPermissions \
  --sig "setAdmin(address,address)" \
  <TOKEN_ADDRESS> <POOL_ADDRESS> \
  --rpc-url $RPC_URL \
  --broadcast
```

### 4) Deploy vault and grant role

```bash
forge script script/Deployer.s.sol:VaultDeployer \
  --sig "run(address)" <TOKEN_ADDRESS> \
  --rpc-url $RPC_URL \
  --broadcast
```

### 5) Allowlist a remote chain and pool

```bash
forge script script/ConfigurePool.s.sol:ConfigurePool \
  --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
  <LOCAL_POOL> <REMOTE_CHAIN_SELECTOR> <REMOTE_POOL> <REMOTE_TOKEN> \
  <OUTBOUND_ENABLED> <OUTBOUND_CAPACITY> <OUTBOUND_RATE> \
  <INBOUND_ENABLED> <INBOUND_CAPACITY> <INBOUND_RATE> \
  --rpc-url $RPC_URL \
  --broadcast
```

### 6) Bridge tokens via script

```bash
forge script script/BridgeTokens.s.sol:BridgeTokens \
  --sig "run(address,address,uint64,uint256,address,address)" \
  <RECEIVER> <ROUTER> <DEST_CHAIN_SELECTOR> <AMOUNT> <LINK_TOKEN> <TOKEN_TO_SEND> \
  --rpc-url $SRC_RPC_URL \
  --broadcast
```

## Development

- Update global interest rate (owner-only, can only decrease): `RebaseToken.setInterestRate`.
- Users inherit their rate on first mint or first receipt if balance was zero.
- Use `principalBalanceOf(user)` to read minted amount excluding accrued interest.
- `Vault.redeem(type(uint256).max)` redeems full balance.

## File map

- `src/RebaseToken.sol`: ERC20 + rebase logic and role-gated mint/burn
- `src/Vault.sol`: ETH vault, deposit/redeem flows
- `src/RebaseTokenPool.sol`: CCIP `TokenPool` adapter with user rate propagation
- `script/*.s.sol`: deploy, permissioning, pool configuration, bridging
- `test/RebaseToken.t.sol`: unit tests for vault and token logic
- `test/CrossChain.t.sol`: end-to-end multi-fork CCIP bridge test

## License

MIT