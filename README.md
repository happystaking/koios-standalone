# koios-standalone

Intended for use on Debian-based systems where all Koios dependencies (cardano-node, postgresql, db-sync, submit-api, etc.) have been independently installed to create the final configuration to become a Koios instance provider.

This script is not part of guild-operators or cntools, but it does require the koios-artifacts repository which is automatically downloaded by the script. When running the script it will ask you for some paths and URL's whereafter it will install configuration files, prepare the database and create a `koios` directory in `/usr/local/bin` with some jobs that will be periodically executed by systemd.

In case pg_bech32 needs to be installed the script will install a few packages to build (in `~/src`) and install the pg_bech32 extension system-wide and enable it in PostgreSQL.

There are several assumptions and pre-conditions:

 - The system users for PostgREST and HAProxy exist
 - You can `psql cexplorer` (or another db) and you can grant
 - The db-sync schema version matches the version in koios-artifacts
 - You intend to run this script for mainnet (testnets are not supported)
 - You are using the [`db-sync-config.json`](https://raw.githubusercontent.com/cardano-community/guild-operators/refs/heads/alpha/files/configs/mainnet/db-sync-config.json) from the [guild-operators](https://github.com/cardano-community/guild-operators) repository

Run `setup.sh` to start the configuration on your system.