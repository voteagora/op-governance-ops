#!/bin/bash

# Default values
DEFAULT_TIMELOCK="0x0eDd4B2cCCf41453D8B5443FBB96cc577d1d06bF"
DEFAULT_RPC="https://rpc.ankr.com/optimism"
TIMELOCK_ADDRESS=$DEFAULT_TIMELOCK
RPC_ARGS="--rpc-url $DEFAULT_RPC"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --rpc-url)
      RPC_ARGS="--rpc-url $2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [timelock_address] [--rpc-url <rpc_url>]"
      echo ""
      echo "Parameters:"
      echo "  timelock_address: The address of the TimelockController contract"
      echo "                   (defaults to $DEFAULT_TIMELOCK)"
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

echo "Using timelock address: $TIMELOCK_ADDRESS"
echo "Using RPC URL: $(echo $RPC_ARGS | sed 's/--rpc-url //')"

# Default block range
FROM_BLOCK="128528629"
TO_BLOCK="latest"

# CANCELLER_ROLE = keccak256("CANCELLER_ROLE")
CANCELLER_ROLE=$(cast keccak 'CANCELLER_ROLE')
echo "CANCELLER_ROLE hash: $CANCELLER_ROLE"

# The signature of RoleGranted event
GRANT_EVENT_SIG="RoleGranted(bytes32,address,address)"
# The signature of RoleRevoked event
REVOKE_EVENT_SIG="RoleRevoked(bytes32,address,address)"

echo "Fetching RoleGranted events..."
GRANT_LOGS=$(cast logs $RPC_ARGS \
  --from-block $FROM_BLOCK \
  --to-block $TO_BLOCK \
  --address $TIMELOCK_ADDRESS \
  "$GRANT_EVENT_SIG")

echo "Fetching RoleRevoked events..."
REVOKE_LOGS=$(cast logs $RPC_ARGS \
  --from-block $FROM_BLOCK \
  --to-block $TO_BLOCK \
  --address $TIMELOCK_ADDRESS \
  "$REVOKE_EVENT_SIG")

# Create temporary files
GRANTS_FILE=$(mktemp)
REVOKES_FILE=$(mktemp)

# Filter grant logs by CANCELLER_ROLE
if [ ! -z "$GRANT_LOGS" ]; then
  echo "Filtering RoleGranted events for CANCELLER_ROLE..."
  echo "$GRANT_LOGS" | while read -r line; do
    # Check if this is a line containing topics
    if [[ "$line" == *"topics:"* ]]; then
      # Read the next line which has the first topic (topics[0])
      read -r topic0
      # Read the next line which has the second topic (topics[1])
      read -r topic1
      
      # Extract just the hash value, trimming whitespace
      role_hash=$(echo "$topic1" | tr -d '[:space:]' | sed 's/.*0x/0x/')
      
      # If this role matches CANCELLER_ROLE
      if [[ "$role_hash" == "$CANCELLER_ROLE" ]]; then
        # Read the next line which has the account address (topics[2])
        read -r topic2
        # Extract and clean up the address
        account=$(echo "$topic2" | tr -d '[:space:]' | sed 's/.*0x/0x/' | sed 's/0x000000000000000000000000/0x/')
        echo "$account" >> $GRANTS_FILE
      fi
    fi
  done
else
  echo "No RoleGranted events found"
fi

# Filter revoke logs by CANCELLER_ROLE
if [ ! -z "$REVOKE_LOGS" ]; then
  echo "Filtering RoleRevoked events for CANCELLER_ROLE..."
  echo "$REVOKE_LOGS" | while read -r line; do
    # Check if this is a line containing topics
    if [[ "$line" == *"topics:"* ]]; then
      # Read the next line which has the first topic (topics[0])
      read -r topic0
      # Read the next line which has the second topic (topics[1])
      read -r topic1
      
      # Extract just the hash value, trimming whitespace
      role_hash=$(echo "$topic1" | tr -d '[:space:]' | sed 's/.*0x/0x/')
      
      # If this role matches CANCELLER_ROLE
      if [[ "$role_hash" == "$CANCELLER_ROLE" ]]; then
        # Read the next line which has the account address (topics[2])
        read -r topic2
        # Extract and clean up the address
        account=$(echo "$topic2" | tr -d '[:space:]' | sed 's/.*0x/0x/' | sed 's/0x000000000000000000000000/0x/')
        echo "$account" >> $REVOKES_FILE
      fi
    fi
  done
else
  echo "No RoleRevoked events found"
fi

# Find accounts that have the role (granted but not revoked)
echo ""
echo "Addresses currently holding CANCELLER_ROLE:"
echo "-----------------------------------------"

if [ ! -s "$GRANTS_FILE" ]; then
  echo "No addresses found with CANCELLER_ROLE."
else
  # Process each granted address
  while read -r ACCOUNT; do
    # Check if the account was later revoked
    if ! grep -q "$ACCOUNT" "$REVOKES_FILE"; then
      echo "$ACCOUNT"
      
      # Optionally verify each address still has the role using hasRole
      HAS_ROLE=$(cast call $TIMELOCK_ADDRESS "hasRole(bytes32,address)(bool)" $CANCELLER_ROLE $ACCOUNT $RPC_ARGS)
      echo "  Verified with hasRole(): $HAS_ROLE"
    fi
  done < "$GRANTS_FILE"
fi

# Clean up
rm $GRANTS_FILE
rm $REVOKES_FILE