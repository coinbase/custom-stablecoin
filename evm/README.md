# Stablecoin -- EVM

Solidity implementation of the Stablecoin system using a beacon proxy pattern with OpenZeppelin contracts.

## Features

- **Beacon Proxy Upgradeability** -- All stablecoin proxies share a single `Stablecoin` implementation via a `TwoStepUpgradeableBeacon`; upgrades apply atomically across every deployed instance
- **ERC-7201 Namespaced Storage** -- Collision-resistant storage layout across all mixin contracts
- **Mint Rate Limiting** -- Each minter has an independent capacity that replenishes over a configurable rolling interval
- **Blocklist** -- Addresses can be blocked from sending, receiving, or approving token transfers
- **Role-Based Access Control** -- Granular roles with separated concerns:
  - `DEFAULT_ADMIN_ROLE` -- Role and upgrade management (single holder, two-step transfer with configurable delay)
  - `MINT_ROLE` -- Mint tokens up to the configured rate limit
  - `MINT_RATE_LIMIT_ROLE` -- Update rate-limit configurations for existing minters
  - `BURN_ROLE` -- Burn the caller's own tokens
  - `BLOCKLIST_ROLE` / `UNBLOCKLIST_ROLE` -- Add or remove addresses from the blocklist
  - `PAUSE_ROLE` / `UNPAUSE_ROLE` -- Pause and unpause all token transfers
  - `METADATA_ROLE` -- Update the contract-level metadata URI (ERC-7572)

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)

## Build

```sh
forge build
```

## Test

```sh
forge test -vvv
```

## Format

```sh
forge fmt --check
```

## Deploy

Copy `.env.example` to `.env`, fill in the values, then run the deployment script. `RPC_URL` should point to an RPC endpoint for the target network (e.g., from [Alchemy](https://www.alchemy.com/) or [Infura](https://www.infura.io/)):

```sh
cp .env.example .env
# edit .env with your values

export $(cat .env | xargs)
export RPC_URL=<https://your-rpc-endpoint>

forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

The script deploys: `Stablecoin` implementation → `TwoStepUpgradeableBeacon` → `StablecoinFactory` implementation → `ERC1967Proxy` wrapping the factory → one initial `Stablecoin` proxy via the factory.

Optional token parameters can be overridden via environment variables:

| Variable | Default |
|---|---|
| `TOKEN_NAME` | `USD Stablecoin` |
| `TOKEN_SYMBOL` | `USDS` |
| `TOKEN_DECIMALS` | `6` |

## Project Structure

```
evm/
├── src/
│   ├── Stablecoin.sol                  # ERC-20 stablecoin implementation
│   ├── StablecoinFactory.sol           # UUPS-upgradeable factory (CREATE2 deploys)
│   ├── TwoStepUpgradeableBeacon.sol    # Beacon with two-step ownership transfer
│   ├── MutableBeaconProxy.sol          # Proxy that can swap its beacon
│   ├── interfaces/                     # Solidity interfaces
│   └── lib/
│       ├── Blocklist.sol               # Blocklist mixin
│       ├── RateLimit.sol               # Rolling rate-limit mixin
│       ├── TokenMetadata.sol           # Custom decimals + ERC-7572 contractURI mixin
│       └── ERC3009Upgradeable.sol      # ERC-3009 transfer-with-authorization mixin
├── script/
│   └── Deploy.s.sol                    # Full system deployment script
├── test/
│   ├── unit/                           # Per-function unit tests
│   ├── integration/                    # End-to-end workflow tests
│   ├── attack/                         # Adversarial scenario tests
│   ├── benchmark/                      # Gas benchmark tests
│   └── lib/                            # Test base contracts and mocks
├── foundry.toml                        # Foundry configuration
└── .env.example                        # Required environment variables
```

## Dependencies

| Dependency | Purpose |
|---|---|
| [OpenZeppelin Contracts Upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable) | Access control, ERC-20 extensions, proxy utilities |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) | ERC-1967 utils, CREATE2, UUPS |
| [forge-std](https://github.com/foundry-rs/forge-std) | Foundry testing and scripting standard library |
