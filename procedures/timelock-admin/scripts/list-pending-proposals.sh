#!/bin/bash

# Default values
DEFAULT_TIMELOCK="0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF"
DEFAULT_RPC="https://rpc.ankr.com/optimism"
DEFAULT_OP_TOKEN="0x4200000000000000000000000000000000000042" # OP token address
TIMELOCK_ADDRESS=$DEFAULT_TIMELOCK
RPC_ARGS="--rpc-url $DEFAULT_RPC"
TYPE="pending" # Default type

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --rpc-url)
      RPC_ARGS="--rpc-url $2"
      shift 2
      ;;
    --type)
      if [[ "$2" == "pending" || "$2" == "cancelled" || "$2" == "executed" ]]; then
        TYPE="$2"
        shift 2
      else
        echo "Error: Invalid type. Must be one of: pending, cancelled, executed"
        exit 1
      fi
      ;;
    --help)
      echo "Usage: $0 [timelock_address] [--rpc-url <rpc_url>] [--type <type>]"
      echo ""
      echo "Parameters:"
      echo "  timelock_address: The address of the TimelockController contract"
      echo "                   (defaults to $DEFAULT_TIMELOCK)"
      echo "  --rpc-url <url>: The RPC endpoint URL to use"
      echo "                   (defaults to $DEFAULT_RPC)"
      echo "  --type <type>:   Type of proposals to display: pending, cancelled, or executed"
      echo "                   (defaults to pending)"
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

echo "Using timelock address: $TIMELOCK_ADDRESS"
echo "Using RPC URL: $(echo $RPC_ARGS | sed 's/--rpc-url //')"
echo "Showing $TYPE proposals"

# The signature of CallScheduled event
CALL_SCHEDULED_EVENT_SIG="CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)"
# The signature of Cancelled event
CANCELLED_EVENT_SIG="Cancelled(bytes32)"
# The signature of CallExecuted event
CALL_EXECUTED_EVENT_SIG="CallExecuted(bytes32,uint256,address,uint256,bytes)"

# Default block range - starting from Optimism Bedrock deployment
FROM_BLOCK="105235063"
TO_BLOCK="latest"

echo "Fetching CallScheduled events..."
SCHEDULED_LOGS=$(cast logs $RPC_ARGS \
  --from-block $FROM_BLOCK \
  --to-block $TO_BLOCK \
  --address $TIMELOCK_ADDRESS \
  "$CALL_SCHEDULED_EVENT_SIG")

echo "Fetching Cancelled events..."
CANCELLED_LOGS=$(cast logs $RPC_ARGS \
  --from-block $FROM_BLOCK \
  --to-block $TO_BLOCK \
  --address $TIMELOCK_ADDRESS \
  "$CANCELLED_EVENT_SIG")

echo "Fetching CallExecuted events..."
EXECUTED_LOGS=$(cast logs $RPC_ARGS \
  --from-block $FROM_BLOCK \
  --to-block $TO_BLOCK \
  --address $TIMELOCK_ADDRESS \
  "$CALL_EXECUTED_EVENT_SIG")

# Create temporary files
OPERATION_IDS_FILE=$(mktemp)
SCHEDULED_FILE=$(mktemp)
CANCELLED_FILE=$(mktemp)
EXECUTED_FILE=$(mktemp)

# Parse scheduled logs
if [ ! -z "$SCHEDULED_LOGS" ]; then
  echo "Processing scheduled operations..."
  
  # Process each log entry
  current_block=""
  current_tx=""
  current_op_id=""
  current_data=""
  
  echo "$SCHEDULED_LOGS" | while IFS= read -r line; do
    # Extract block number
    if [[ "$line" == *"blockNumber:"* ]]; then
      current_block=$(echo "$line" | sed 's/.*blockNumber: *//')
    fi
    
    # Extract transaction hash
    if [[ "$line" == *"transactionHash:"* ]]; then
      current_tx=$(echo "$line" | sed 's/.*transactionHash: *//')
    fi
    
    # Extract operation ID from topics
    if [[ "$line" == *"topics:"* ]]; then
      # Read the next line for the operation ID
      read -r topic0
      # The next line contains the operation ID (first topic)
      read -r op_id_line
      current_op_id=$(echo "$op_id_line" | tr -d '[:space:]')
    fi
    
    # Extract data field
    if [[ "$line" == *"data: 0x"* ]]; then
      current_data=$(echo "$line" | sed 's/.*data: *//')
      
      # Get the block timestamp - extract only the numeric part
      block_timestamp=$(cast block $current_block $RPC_ARGS | grep timestamp | sed 's/timestamp *//g' | awk '{print $1}')
      
      # Process the data field - manually decoding
      # Remove 0x prefix
      data_no_prefix=$(echo "$current_data" | sed 's/^0x//')
      
      # Extract target address (starts at position 0, 64 hex chars in length)
      # Address is in the last 20 bytes of the 32 byte field
      target_with_padding=${data_no_prefix:0:64}
      target="0x${target_with_padding:24:40}"
      
      # Extract value (starts at position 64, 64 hex chars in length)
      value_hex=${data_no_prefix:64:64}
      # Convert to decimal using printf instead of bc
      value_dec=$(printf "%d" "0x${value_hex}" 2>/dev/null || echo "0")
      
      # Skip data pointer (position 128, 64 hex chars)
      
      # Extract predecessor (starts at position 192, 64 hex chars)
      predecessor_hex=${data_no_prefix:192:64}
      
      # Extract delay (starts at position 256, 64 hex chars)
      delay_hex=${data_no_prefix:256:64}
      delay=$(printf "%d" "0x${delay_hex}" 2>/dev/null || echo "0")
      
      # Extract function call data (optional, if it exists)
      function_data=""
      if [ ${#data_no_prefix} -gt 320 ]; then
        # Get the length of the function data
        data_length_hex=${data_no_prefix:320:64}
        data_length=$(printf "%d" "0x${data_length_hex}" 2>/dev/null || echo "0")
        
        # Extract the actual function data if present
        if [ -n "$data_length" ] && [ "$data_length" -gt 0 ]; then
          # Function data starts after the length field
          function_data=${data_no_prefix:384}
          
          # Look for OP token transfers
          target_lower=$(echo "$target" | tr '[:upper:]' '[:lower:]')
          op_token_lower=$(echo "$DEFAULT_OP_TOKEN" | tr '[:upper:]' '[:lower:]')
          if [[ "$target_lower" == "$op_token_lower" && "${function_data:0:8}" == "a9059cbb" ]]; then
            # This is an OP token transfer
            # Extract recipient (next 32 bytes / 64 hex chars)
            recipient_with_padding=${function_data:8:64}
            recipient="0x${recipient_with_padding:24:40}"
            
            # Extract amount (next 32 bytes / 64 hex chars)
            amount_hex=${function_data:72:64}
            # Convert to decimal and to ether units
            amount_wei=$(printf "%d" "0x${amount_hex}" 2>/dev/null || echo "0")
            amount_eth=$(cast --from-wei $amount_wei 2>/dev/null || echo "0")
            
            # Add token transfer info to function data
            function_data="OP Token transfer: $amount_eth OP to $recipient"
          fi
        fi
      fi
      
      # Calculate the ready time
      ready_timestamp=$((block_timestamp + delay))
      
      # Save operation data to file
      echo "$current_op_id,$current_block,$current_tx,$target,$value_dec,$block_timestamp,$delay,$ready_timestamp,$function_data" >> $SCHEDULED_FILE
      
      # Save operation ID
      echo "$current_op_id" >> $OPERATION_IDS_FILE
    fi
  done
fi

# Parse cancelled logs
if [ ! -z "$CANCELLED_LOGS" ]; then
  echo "Processing cancelled operations..."
  
  echo "$CANCELLED_LOGS" | while IFS= read -r line; do
    if [[ "$line" == *"topics:"* ]]; then
      # Read the next line for the event name topic
      read -r topic0
      # Read the next line for the operation ID
      read -r op_id_line
      op_id=$(echo "$op_id_line" | tr -d '[:space:]')
      
      # Save to cancelled file
      echo "$op_id" >> $CANCELLED_FILE
    fi
  done
fi

# Parse executed logs
if [ ! -z "$EXECUTED_LOGS" ]; then
  echo "Processing executed operations..."
  
  echo "$EXECUTED_LOGS" | while IFS= read -r line; do
    if [[ "$line" == *"topics:"* ]]; then
      # Read the next line for the event name topic
      read -r topic0
      # Read the next line for the operation ID
      read -r op_id_line
      op_id=$(echo "$op_id_line" | tr -d '[:space:]')
      
      # Save to executed file
      echo "$op_id" >> $EXECUTED_FILE
    fi
  done
fi

# Find proposals based on selected type
echo ""
if [[ "$TYPE" == "pending" ]]; then
  echo "Pending proposals in timelock:"
  echo "============================="
elif [[ "$TYPE" == "cancelled" ]]; then
  echo "Cancelled proposals in timelock:"
  echo "==============================="
elif [[ "$TYPE" == "executed" ]]; then
  echo "Executed proposals in timelock:"
  echo "=============================="
fi

PROPOSAL_COUNT=0

if [ ! -s "$OPERATION_IDS_FILE" ]; then
  echo "No proposals found in the timelock."
else
  # Current timestamp for calculating time left
  current_timestamp=$(date +%s)
  
  while IFS=, read -r op_id block_number tx_hash target value block_timestamp delay ready_timestamp function_data; do
    # Filter based on type
    if [[ "$TYPE" == "pending" ]]; then
      # Skip if cancelled
      if grep -q "$op_id" "$CANCELLED_FILE"; then
        continue
      fi
      
      # Skip if executed
      if grep -q "$op_id" "$EXECUTED_FILE"; then
        continue
      fi
      
      # Check if this operation is still pending by calling the contract
      op_state=$(cast call $TIMELOCK_ADDRESS "getOperationState(bytes32)(uint8)" $op_id $RPC_ARGS)
      
      # 0=Unset, 1=Waiting, 2=Ready, 3=Done
      if [[ "$op_state" == "0" || "$op_state" == "3" ]]; then
        continue
      fi
      
      # Calculate time remaining or if it's ready
      if [[ "$op_state" == "1" ]]; then
        time_left=$((ready_timestamp - current_timestamp))
        days=$((time_left / 86400))
        hours=$(( (time_left % 86400) / 3600 ))
        minutes=$(( (time_left % 3600) / 60 ))
        status="Waiting - Ready in ${days}d ${hours}h ${minutes}m"
      else
        status="Ready for execution"
      fi
    elif [[ "$TYPE" == "cancelled" ]]; then
      # Only include if cancelled
      if ! grep -q "$op_id" "$CANCELLED_FILE"; then
        continue
      fi
      status="Cancelled"
    elif [[ "$TYPE" == "executed" ]]; then
      # Only include if executed
      if ! grep -q "$op_id" "$EXECUTED_FILE"; then
        continue
      fi
      status="Executed"
    fi
    
    # This is a matching proposal - increment counter
    PROPOSAL_COUNT=$((PROPOSAL_COUNT + 1))
    
    # Convert value from wei to ether for readability
    value_in_eth=$(cast --from-wei $value 2>/dev/null || echo "$value")
    
    # Extract OP tokens at risk
    op_tokens_at_risk="0"
    if [[ "$function_data" == "OP Token transfer: "* ]]; then
      op_tokens_at_risk=$(echo "$function_data" | sed 's/OP Token transfer: \([0-9.]*\) OP to.*/\1/')
    fi
    
    # Print proposal information
    echo "Proposal ID: $op_id"
    echo "Block: $block_number"
    echo "Tx: $tx_hash"
    echo "Created: $(date -r $block_timestamp 2>/dev/null || date -d "@$block_timestamp" 2>/dev/null || echo "Timestamp: $block_timestamp")"
    echo "Target: $target"
    echo "Value: $value_in_eth ETH"
    echo "OP Tokens at risk: $op_tokens_at_risk OP"
    echo "Status: $status"
    echo "Ready at: $(date -r $ready_timestamp 2>/dev/null || date -d "@$ready_timestamp" 2>/dev/null || echo "Timestamp: $ready_timestamp")"
    echo "----------------------------"
    
  done < "$SCHEDULED_FILE"
  
  if [ "$PROPOSAL_COUNT" -eq 0 ]; then
    if [[ "$TYPE" == "pending" ]]; then
      echo "No pending proposals found in the timelock."
    elif [[ "$TYPE" == "cancelled" ]]; then
      echo "No cancelled proposals found in the timelock."
    elif [[ "$TYPE" == "executed" ]]; then
      echo "No executed proposals found in the timelock."
    fi
  fi
fi

# Clean up
rm $OPERATION_IDS_FILE
rm $SCHEDULED_FILE
rm $CANCELLED_FILE
rm $EXECUTED_FILE

echo ""
if [[ "$TYPE" == "pending" ]]; then
  echo "Total pending proposals: $PROPOSAL_COUNT"
elif [[ "$TYPE" == "cancelled" ]]; then
  echo "Total cancelled proposals: $PROPOSAL_COUNT"
elif [[ "$TYPE" == "executed" ]]; then
  echo "Total executed proposals: $PROPOSAL_COUNT"
fi