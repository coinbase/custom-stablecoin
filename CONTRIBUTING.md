# Contributing to Stablecoin

Thanks for your interest in contributing! This guide covers how to set up a development environment, run tests, and submit pull requests.

## Prerequisites

- Git with [signed commits enabled](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
- See each implementation's README for chain-specific tooling requirements:
  - [EVM](evm/README.md) -- requires [Foundry](https://book.getfoundry.sh/getting-started/installation)

## Getting Started

1. Fork this repository and clone your fork:

```sh
git clone https://github.com/<your-username>/custom-stablecoin.git
cd custom-stablecoin
```

2. Initialize submodules:

```sh
git submodule update --init --recursive
```

3. Navigate to the implementation you're working on and follow its README for build and test instructions.

## Repository Structure

```
custom-stablecoin/
├── evm/          # EVM (Solidity) implementation
├── LICENSE
├── SECURITY.md
├── CONTRIBUTING.md
└── .github/
    ├── workflows/
    └── PULL_REQUEST_TEMPLATE.md
```

Each implementation directory is self-contained with its own source, tests, scripts, and README.

## Development Workflow

### Branching

1. Create a feature branch from `main`:

```sh
git checkout -b your-feature-name
```

2. Make your changes and ensure all checks pass. See the implementation's README for the exact commands.

3. Commit with a [signed commit](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits).
4. Push to your fork and open a pull request against `main`.

## Pull Request Guidelines

- Fill out the pull request template completely.
- Keep pull requests focused -- one logical change per PR.
- Include tests for new functionality or bug fixes.
- Ensure all CI checks pass before requesting review.
- All commits must be signed.

## Getting Help

- Open a [GitHub Issue](../../issues) to report bugs or request features.
- For security vulnerabilities, follow the process in [SECURITY.md](SECURITY.md) -- do **not** file a public issue.
