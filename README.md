## Serpentor

<img src="cobra.png" width="200"> 


[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

A set of smart contracts tools for governance written in vyper

## Setup

This project uses [foundry](https://github.com/foundry-rs/foundry) and [apeworx](https://github.com/ApeWorX/ape) to combine both unit test, fuzz tests with integration tests in python.

Install ape framework. 

See [ape quickstart guide](https://docs.apeworx.io/ape/stable/userguides/quickstart.html)

Install [foundry](https://github.com/foundry-rs/foundry)

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
