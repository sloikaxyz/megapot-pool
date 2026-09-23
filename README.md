# Megapot Pool

A Solidity contract for pooling tickets in the **Megapot v1 protocol**. Participants buy tickets through `JackpotPool` using the jackpot's ERC-20 token, and winnings are shared proportionally to each participant's fee-adjusted tickets for each round. Tickets can be purchased for another recipient, and participants can withdraw their share of winnings across rounds.

This project targets the legacy v1 protocol: Megapot v2 launched on **March 17, 2026**, and v1 wound down on **March 24, 2026**, ending new ticket purchases and deposits ([official transition notice](https://stats.megapot.io/)).

Megapot v1 jackpot contract on Base mainnet: [`0xbEDd4F2beBE9E3E636161E644759f3cbe3d51B95`](https://basescan.org/address/0xbEDd4F2beBE9E3E636161E644759f3cbe3d51B95) (BaseScan; address verified against the [legacy app](https://v1.megapot.io/)).

Built and tested with Foundry.

## Foundry reference

[Foundry documentation](https://book.getfoundry.sh/)

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

Generic script command (replace the placeholder with your deployment script; this project does not include one):

```shell
$ forge script <script_path>:<script_contract> --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
