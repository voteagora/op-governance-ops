#!/bin/bash

# Default values
DEFAULT_TIMELOCK="0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF"
DEFAULT_RPC="https://rpc.ankr.com/optimism"
TIMELOCK_ADDRESS=$DEFAULT_TIMELOCK
RPC_ARGS="--rpc-url $DEFAULT_RPC"
PROPOSAL_ID=""

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
    --help)
      echo "Usage: $0 [timelock_address] [--proposal <id_or_all>] [--rpc-url <rpc_url>]"
      echo ""
      echo "Parameters:"
      echo "  timelock_address: The address of the TimelockController contract"
      echo "                   (defaults to $DEFAULT_TIMELOCK)"
      echo "  --proposal <id_or_all>: The proposal ID to cancel, or 'all' to cancel all pending proposals"
      echo "                        This parameter is required"
      echo "  --rpc-url <url>: The RPC endpoint URL to use"
      echo "                   (defaults to $DEFAULT_RPC)"
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

# Generate calldata for cancelling a specific proposal
generate_cancel_calldata() {
  local proposal_id=$1
  
  # Check if proposal exists and is pending
  op_state=$(cast call $TIMELOCK_ADDRESS "getOperationState(bytes32)(uint8)" $proposal_id $RPC_ARGS)
  
  # 0=Unset, 1=Waiting, 2=Ready, 3=Done
  if [[ "$op_state" == "0" ]]; then
    echo "Error: Proposal ID $proposal_id does not exist"
    return 1
  elif [[ "$op_state" == "3" ]]; then
    echo "Error: Proposal ID $proposal_id is already executed"
    return 1
  fi
  
  # Generate calldata for the cancel function
  local calldata=$(cast calldata "cancel(bytes32)" $proposal_id)
  
  echo "Proposal ID: $proposal_id"
  echo "Operation State: $([ "$op_state" == "1" ] && echo "Waiting" || echo "Ready")"
  echo "Cancel Calldata: $calldata"
  echo ""
}

# Main execution

# If proposal ID is "all"
if [[ "$PROPOSAL_ID" == "all" ]]; then
  echo "Generating calldata to cancel all pending proposals..."
  
  # Create a temporary file to store proposal IDs
  PENDING_FILE=$(mktemp)
  
  # Use list-pending-proposals.sh to get all pending proposals
  # Use grep to extract just the proposal IDs
  # Redirect stderr to /dev/null to hide "Fetching..." messages
  ./list-timelock-proposals.sh $TIMELOCK_ADDRESS $RPC_ARGS --type pending 2>/dev/null | 
    grep -A1 "Proposal ID:" | 
    grep -v "Proposal ID:" | 
    grep -v "\-\-" | 
    grep "0x" > $PENDING_FILE
  
  # Check if we found any pending proposals
  if [ ! -s "$PENDING_FILE" ]; then
    echo "No pending proposals found in the timelock."
    rm -f "$PENDING_FILE" 2>/dev/null
    exit 0
  fi
  
  # Generate calldata for each pending proposal
  echo "Cancel calldata for all pending proposals:"
  echo "========================================"
  
  while read -r op_id; do
    # Clean up any whitespace
    op_id=$(echo "$op_id" | tr -d '[:space:]')
    if [ ! -z "$op_id" ]; then
      generate_cancel_calldata $op_id
    fi
  done < "$PENDING_FILE"
  
  rm -f "$PENDING_FILE" 2>/dev/null
else
  # Single proposal cancellation
  echo "Generating calldata to cancel proposal: $PROPOSAL_ID"
  echo "=============================================="
  
  generate_cancel_calldata $PROPOSAL_ID
fi