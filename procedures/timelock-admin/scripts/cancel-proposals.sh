#!/bin/bash

# Default values
DEFAULT_TIMELOCK="0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF"
DEFAULT_RPC="https://rpc.ankr.com/optimism"
TIMELOCK_ADDRESS=$DEFAULT_TIMELOCK
RPC_ARGS="--rpc-url $DEFAULT_RPC"
PROPOSAL_ID=""
PRIVATE_KEY=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --proposal)
      PROPOSAL_ID="$2"
      shift 2
      ;;
    --rpc-url)
      RPC_ARGS="--rpc-url $2"
      shift 2
      ;;
    --private-key)
      PRIVATE_KEY="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [timelock_address] [--proposal <id_or_all>] [--rpc-url <rpc_url>] [--private-key <key>]"
      echo ""
      echo "Parameters:"
      echo "  timelock_address: The address of the TimelockController contract"
      echo "                   (defaults to $DEFAULT_TIMELOCK)"
      echo "  --proposal <id_or_all>: The proposal ID to cancel, or 'all' to cancel all pending proposals"
      echo "                        This parameter is required"
      echo "  --rpc-url <url>: The RPC endpoint URL to use"
      echo "                   (defaults to $DEFAULT_RPC)"
      echo "  --private-key <key>: Private key starting with 0x to sign and send transaction"
      echo "                      If not provided, will only output the ABI-encoded calldata"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Use --help to see available options"
      exit 1
      ;;
    *)
      # First non-option argument is treated as the timelock address
      TIMELOCK_ADDRESS=$1
      shift
      ;;
  esac
done

# Verify proposal ID is provided
if [ -z "$PROPOSAL_ID" ]; then
  echo "Error: --proposal parameter is required"
  echo "Use --help to see available options"
  exit 1
fi

echo "Using timelock address: $TIMELOCK_ADDRESS"
echo "Using RPC URL: $(echo $RPC_ARGS | sed 's/--rpc-url //')"
[ -n "$PRIVATE_KEY" ] && echo "Using private key: [redacted]"

# Function to process a proposal
process_proposal() {
  local proposal_id=$1
  
  echo "Processing proposal: $proposal_id"
  
  if [ -n "$PRIVATE_KEY" ]; then
    # If private key is provided, send the transaction
    cast send $RPC_ARGS $TIMELOCK_ADDRESS "cancel(bytes32)" "$proposal_id" --private-key "$PRIVATE_KEY"
  else
    # If no private key, just output the ABI-encoded calldata
    local calldata=$(cast calldata "cancel(bytes32)" "$proposal_id")
    echo "ABI-encoded calldata: $calldata"
  fi
}

# Main execution
echo "Starting cancellation process..."
echo "------------------------"

if [ "$PROPOSAL_ID" == "all" ]; then
  # Check if the list script exists
  if [ ! -f "./list-pending-proposals.sh" ]; then
    echo "Error: list-pending-proposals.sh not found in current directory"
    exit 1
  fi
  
  # Make sure the script is executable
  chmod +x ./list-pending-proposals.sh
  
  # Get all pending proposals
  echo "Fetching all pending proposals..."
  proposal_list=$(./list-pending-proposals.sh "$TIMELOCK_ADDRESS" $RPC_ARGS --type pending)
  
  # Extract proposal IDs from the output
  proposal_ids=($(echo "$proposal_list" | grep "Proposal ID:" | sed 's/Proposal ID: //'))
  
  if [ ${#proposal_ids[@]} -eq 0 ]; then
    echo "No pending proposals found"
    exit 0
  fi
  
  echo "Found ${#proposal_ids[@]} pending proposals"
  echo "------------------------"
  
  # Process each proposal
  for id in "${proposal_ids[@]}"; do
    process_proposal "$id"
    echo "------------------------"
  done
  
else
  # Process single specific proposal
  process_proposal "$PROPOSAL_ID"
fi

echo "Cancellation process completed"