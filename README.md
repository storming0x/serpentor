## Serpentor

<p align="center">
    <img src="cobra.png" width="200">
</p>

[![Forge tests](https://github.com/storming0x/serpentor/actions/workflows/forge-tests.yml/badge.svg)](https://github.com/storming0x/serpentor/actions/workflows/forge-tests.yml)
[![Python tests](https://github.com/storming0x/serpentor/actions/workflows/ape-tests.yml/badge.svg)](https://github.com/storming0x/serpentor/actions/workflows/ape-tests.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

A set of smart contracts tools for governance written in vyper

## Requirements

The test environment requires that the `vyper` compiler command can be accessed from your path

[vyper install instructions](https://vyper.readthedocs.io/en/stable/installing-vyper.html)

As an alternative you can also install [vvm](https://github.com/storming0x/vvm-rs)

and run 

```bash
vvm install 0.3.6
```

## Setup

This project uses [foundry](https://github.com/foundry-rs/foundry) and [apeworx](https://github.com/ApeWorX/ape) to combine both unit test, fuzz tests with integration tests in python.

Install ape framework.

See [ape quickstart guide](https://docs.apeworx.io/ape/stable/userguides/quickstart.html)

Install [foundry](https://github.com/foundry-rs/foundry)

Install JS dependencies

```bash
npm install
```

## Build

```bash
forge build
```

## Run tests

```bash
forge test
```

## Run tests with traces

```bash
forge test -vvv
```
**Recommendation**: for faster test times install [vvm-rs](https://github.com/storming0x/vvm-rs). This will add a caching layer to the vyper compiler that improves test times with forge. E.g 32s-> 52ms in local benchmarks

## Build with ape

```bash
ape compile
```

## Run python tests

```bash
ape test
```

## Disclaimer

Code has not been audited

## Acknowledgements

- [snekmate](https://github.com/pcaversaccio/snekmate)
- [vyperDeployer](https://github.com/0xKitsune/Foundry-Vyper/blob/main/lib/utils/VyperDeployer.sol)
