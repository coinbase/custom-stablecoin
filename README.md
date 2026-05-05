# Stablecoin

A production-ready stablecoin with role-based access control, mint rate limiting, blocklisting, and a factory for deploying multiple stablecoin instances from a shared implementation.

## Overview

This repository provides chain-specific implementations of a stablecoin system with a shared set of design goals: upgradeable contracts, granular role-based access control, mint rate limiting, blocklisting, and pause functionality.

### Features

- **Upgradeability** -- Implementations can be upgraded without disrupting existing token holders
- **Mint Rate Limiting** -- Minters operate within a configurable capacity that replenishes over a rolling interval
- **Blocklist** -- Addresses can be blocked from sending, receiving, or approving transfers
- **Pause** -- All transfers can be paused and unpaused independently
- **Role-Based Access Control** -- Granular roles with separated concerns; admin transfer is two-step with a configurable delay

## Implementations

| Chain | Directory | Details |
|---|---|---|
| EVM | [`evm/`](evm/) | Solidity, beacon proxy pattern, OpenZeppelin |

See each implementation's README for chain-specific quickstart, build, test, and deployment instructions.

## Repository Structure

```
custom-stablecoin/
├── evm/                       # EVM (Solidity) implementation
│   └── README.md              # EVM quickstart and project details
├── LICENSE
├── SECURITY.md
├── CONTRIBUTING.md
└── .github/
    └── PULL_REQUEST_TEMPLATE.md
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, coding standards, and the pull request workflow.

## Security

See [SECURITY.md](SECURITY.md) for our security policy and how to report vulnerabilities.

## License

This project is licensed under the Apache 2.0 License. See [LICENSE](LICENSE) for details.
