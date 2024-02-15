#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please install jq to use this script."
    exit 1
fi

# Convert the first argument to uppercase since Coinbase API expects currency symbols in uppercase
CURRENCY=$(echo "$1" | tr '[:lower:]' '[:upper:]')

# Coinbase API URL for spot price
URL="https://api.coinbase.com/v2/prices/$CURRENCY-USD/spot"

# Fetch the spot price of the cryptocurrency
RESPONSE=$(curl -s "$URL")

# Check if the request was successful
if [ $? -ne 0 ]; then
    echo "Failed to retrieve data from Coinbase."
    exit 1
fi

# Parse the price from the response using jq
PRICE=$(echo $RESPONSE | jq -r '.data.amount')

# Check if the price is non-empty
if [ -z "$PRICE" ]; then
    echo "Could not find the price for $CURRENCY."
    exit 1
fi

# Output the price
echo "The current price of $CURRENCY is: $PRICE USD"