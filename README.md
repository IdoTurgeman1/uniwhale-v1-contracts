# uniwhale-v1

## direnv

We're using [direnv](https://direnv.net/) to manage environment variables. Please install it and run `direnv allow` in the project root. You can override env in `.envrc.local`.

## Contract Development

We're using hardhat to compile, test, and deploy Solidity contracts.
For more information please refer to: https://hardhat.org/hardhat-runner/docs

Common tasks:

```bash
# compile contracts
nx compile contracts-core-v1
# clean contracts
nx clean contracts-core-v1
# code lint
nx run-many --target=lint
# tests
nx run-many --target=test
# deploy to a local node
nx deploy contracts-core-v1 --network localhost
```

## Local testing

Tests require forking. We've already setup the shared alchemy key for internal use:

```bash
nx test contracts-core-v1
```

You can also use your API key from Alchemy.

```bash
ARBITRUM_FORK_URL=https://arb-mainnet.g.alchemy.com/v2/<key> nx test-arb contracts-core-v1
ETHEREUM_FORK_URL=https://eth-mainnet.g.alchemy.com/v2/<key> nx test-eth contracts-core-v1
```

## Run local testnet node

To start the local node and prepare everything, simply run: `dev-localnet`.

And if you need data sync and/or liqbot:

```bash
# create network
nx up dev-network

# reset database & hasura for data-sync
nx recreate dev-database
nx serve apps-data-sync --watch false

# start redis for liqbot
nx recreate dev-redis
dev-liqbot
```

Prerequisites:

- Install docker-compose: https://docs.docker.com/compose/install/other/
- Add `127.0.0.1 gateway.docker.internal` to hosts file, e.g. `/etc/hosts` in \*unix systems

When the local node is up, you're be able to access the RPC through `http://127.0.0.1:8545`.
