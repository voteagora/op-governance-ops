# Timelock Proposal Canceller

This script enables cancellation of proposals in Optimism's Timelock contract. It can either cancel a specific proposal or all pending proposals, and can either send the transaction directly or output the required calldata.

## Features

- Allows cancelling a specific proposal or all pending proposals
- Supports private key to send onchain transactions
- When no private key is provided, outputs ABI-encoded calldata, which can be used for manual submission or multisig transactions
- All or specific proposals can be cancelled (batched or individually)

## Requirements

- Foundry (https://book.getfoundry.sh/getting-started/installation) - This script uses Foundry's `cast` tool
- Bash shell environment
- The `list-timelock-proposals.sh` script in the same directory (when cancelling all proposals)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/voteagora/op-governance-ops.git
```

2. Move to the directory:
```bash
cd op-governance-ops/procedures/timelock-admin
```

## Usage

```bash
./cancel-timelock-proposals.sh [timelock_address] [--proposal <id_or_all>] [--rpc-url <rpc_url>] [--private-key <key>] [--help]
```

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `timelock_address` | The address of the `TimelockController` contract | 0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF |
| `--proposal <id_or_all>` | The proposal ID to cancel (32-byte hex starting with 0x) or 'all' for all pending proposals | Required parameter, no default |
| `--rpc-url <url>` | The RPC endpoint URL to use | https://rpc.ankr.com/optimism |
| `--private-key <key>` | Private key to sign and send transaction. If omitted, outputs calldata only | None |
| `--help` | Display help information | - |

## How It Works

The script:

1. For a specific proposal ID:
   - Either sends a cancellation transaction or generates calldata
2. For "all" proposals:
   - Uses `list-timelock-proposals.sh` to fetch all pending proposals
   - Processes each proposal individually
3. Depending on `--private-key`:
   - With key: Sends transaction using `cast send`
   - Without key: Outputs ABI-encoded calldata using `cast abi-encode`

## Example Output

```
> ./cancel-proposals.sh --proposal all
Using timelock address: 0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF
Using RPC URL: https://rpc.ankr.com/optimism
Starting cancellation process...
------------------------
Fetching all pending proposals...
Found 1 pending proposals
------------------------
Processing proposal: 0x15a9d5347cda8ddfbef031137bfbcb3e5d8dbf885b030516ff4456d715255bc5
ABI-encoded calldata: 0xc4d252f515a9d5347cda8ddfbef031137bfbcb3e5d8dbf885b030516ff4456d715255bc5
------------------------
Cancellation process completed
```

## Examples

### Get calldata to cancel a single proposal
```bash
./cancel-timelock-proposals.sh --proposal 0x15a9d5347cda8ddfbef031137bfbcb3e5d8dbf885b030516ff4456d715255bc5
```

### Get calldatas to cancel all pending proposals
```bash
./cancel-timelock-proposals.sh --proposal all
```

### Cancel a single proposal with a private key
```bash
./cancel-timelock-proposals.sh --proposal 0x15a9d5347cda8ddfbef031137bfbcb3e5d8dbf885b030516ff4456d715255bc5 --private-key 0x...
```

### Cancel all pending proposals with a private key
```bash
./cancel-timelock-proposals.sh --proposal all --private-key 0x...
```