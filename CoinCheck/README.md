# CoinCheck

Get crypto prices with a simple bash command.

## Prerequisites

- `jq` - Command-line JSON processor

## Installation

1. Clone this repo or just grab the `coincheck.sh` script.
2. Make it executable:

    chmod +x coincheck.sh

## Usage

Run the script with the crypto symbol as an argument. Lowercase, uppercase, scream case - we don't judge.

    ./coincheck.sh ETH # Boom, ETH real-time value.
    ./coincheck.sh btc # Boom, BTC real-time value.

## Disclaimer

- This script hits the Coinbase API. Don't abuse it, or they might get grumpy.
- Prices are in USD because 'Murica.

## License and Authorship

Author: @pwnjack

MIT - do what you want, but don't blame me if your crypto tanks.