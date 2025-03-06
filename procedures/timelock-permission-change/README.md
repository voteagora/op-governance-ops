# Timelock CANCELLER_ROLE Holder Finder

This script identifies and verifies all addresses that currently hold the `CANCELLER_ROLE` in Optimism's Timelock contract by analyzing both historical events and current contract state.

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation) - This script uses Foundry's `cast` tool
- Bash shell environment

## Installation

1. Clone the repository:
```bash
git clone https://github.com/voteagora/op-governance-ops.git
```

2. Move to the directory:
```bash
cd op-governance-ops/procedures/timelock-permission-change
```

## Usage

```bash
./get-canceller-role.sh [timelock_address] [--rpc-url <rpc_url>] [--help]
```

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `timelock_address` | The address of the `TimelockController` contract | 0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF |
| `--rpc-url <url>` | The RPC endpoint URL to use | https://rpc.ankr.com/optimism |
| `--help` | Display help information | - |

## How It Works

The script:

1. Calculates the keccak256 hash of `CANCELLER_ROLE` to get the role identifier
2. Fetches all `RoleGranted` and `RoleRevoked` events from the `TimelockController`
3. Filters events to find only those related to the `CANCELLER_ROLE`
4. Identifies addresses that were granted the role but never had it revoked
5. Verifies each address still has the role by calling the contract's `hasRole()` function

## Example Output

```
> ./get-canceller-role.sh
Using timelock address: 0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF
Using RPC URL: https://rpc.ankr.com/optimism
CANCELLER_ROLE hash: 0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783
Fetching RoleGranted events...
Fetching RoleRevoked events...
Filtering RoleGranted events for CANCELLER_ROLE...
No RoleRevoked events found

Addresses currently holding CANCELLER_ROLE:
-----------------------------------------
0xcdf27f107725988f2261ce2256bdfcde8b382b10
  Verified with hasRole(): true
```

## Background on the CANCELLER_ROLE

In the `TimelockController`, the `CANCELLER_ROLE` is a privileged role that allows addresses to cancel proposed operations before they're executed. This is an important administrative function that lets governance cancel potentially problematic proposals.

By default, all addresses with the `PROPOSER_ROLE` also receive the `CANCELLER_ROLE` during contract initialization.

## Limitations

- The script only tracks role changes through events, so if roles were modified through other means (like `delegatecall` or contract redeployment), these changes might not be detected
- The default starting block is set to 128528629, which is the deployment block of the `TimelockController` contract.
- The default RPC is public, so it might occasionally be slow, unresponsive or rate-limited.