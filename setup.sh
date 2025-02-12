#!/bin/bash

# Function definitions
scriptDir=$(dirname "$(readlink -f "$0")")
function askInput () { read -p "$1: " input; echo $input; }
function askDefault () { read -p "$1 [$2]: " input; input=${input:-$2}; echo $input; }
function askConfirmation () { read -p "$1 (y/n): " input; if [[ $input == [yY] ]]; then echo 1; else echo 0; fi; }
function cmdStatus () { if [[ $? -eq 0 ]]; then echo $1; else exit 1; fi; }

# Script execution
echo "
This script is meant to create the final configuration to become a Koios instance provider and depends on koios-artifacts and guild-operators repositories to do so.
It is intended for use on Debian-based systems where all Koios dependencies (cardano-node, postgresql, db-sync, submit-api, etc.) have been independently installed.
Before you proceed, please ensure that:

 - The system users for PostgREST and HAProxy exist
 - You can 'psql cexplorer' (or another db) and you can grant
 - The db-sync schema version matches the version in koios-artifacts
 - You intend to run this script for mainnet (testnets are not supported)
 - You are using the db-sync-config.json from the "guild-operators" repository

This script will change the configuration for PostgREST and HAProxy and create a 'koios' directory in /usr/local/bin with some scripts that will be periodically executed by systemd.
In case pg_bech32 needs to be installed the script will install a few packages to build (in ~/src) and install the pg_bech32 extension system-wide.
"

autoCardanoMetricsUrl=$(sudo netstat -tupln | grep 12798 | awk '{print $4}' | head -n 1)
autoSubmitApiUrl=$(sudo netstat -tupln | grep 8090 | awk '{print $4}' | head -n 1)
autoOgmiosUrl=$(sudo netstat -tupln | grep 1337 | awk '{print $4}' | head -n 1)
autoDbSyncMetricsAddr=$(sudo netstat -tulpn | grep cardano-node | awk '{print $4}' | grep 0\.0\.0\.0 | cut -d ":" -f 1)
autoDbSyncMetricsPort=$(sudo netstat -tulpn | grep cardano-db-sync | awk '{print $4}' | grep 0\.0\.0\.0 | cut -d ":" -f 2)

echo "Cardano Node and DB-Sync environments"
cardanoCliPath=$(askDefault " Path to cardano-cli" "`which cardano-cli`")
cardanoSocketPath=$(askDefault " Path to node.socket" "/var/lib/cardano/mainnet/node.socket")
cardanoMetricsUrl=$(askDefault " Metrics URL for cardano-node" "http://${autoCardanoMetricsUrl/0.0.0.0/127.0.0.1}/metrics")
dbSyncMetricsAddr=$(askDefault " Metrics address for cardano-db-sync" "${autoDbSyncMetricsAddr/0.0.0.0/127.0.0.1}")
dbSyncMetricsPort=$(askDefault " Metrics port for cardano-db-sync" "${autoDbSyncMetricsPort}")
echo ""

echo "Cardano Submit API  and Ogmios environments"
submitApiUrl=$(askDefault " Listen address and port for cardano-submit-api" "${autoSubmitApiUrl/0.0.0.0/127.0.0.1}")
ogmiosUrl=$(askDefault " Listen address and port for Ogmios" "${autoOgmiosUrl/0.0.0.0/127.0.0.1}")
echo ""

echo "PostgREST configuration"
grestConfigPath=$(askDefault " PostgREST config dir" "/etc/postgrest")
grestSystemUser=$(askDefault " PostgREST system user" "postgrest")
grestPostgresRole=$(askDefault " PostgREST psql role" "postgrest")
grestPostgresDb=$(askDefault " PostgREST database name" "cexplorer")
grestInstallPgBech32=$(askConfirmation " Install pg_bech32 and create extension in grest?")
echo ""

echo "HAProxy configuration"
haProxyConfigPath=$(askDefault " HAProxy config dir" "/etc/haproxy")
haProxySystemUser=$(askDefault " HAProxy system user" "haproxy")
koiosUrl=$(askDefault " Koios URL" "api.koios.rest")
echo ""

echo "Working: Cloning koios-artifacts into /tmp"
sudo rm -Rf /tmp/koios-artifacts && \
git clone -q https://github.com/cardano-community/koios-artifacts.git /tmp/koios-artifacts
cmdStatus "Success: Cloned koios-artifacts into /tmp"

echo "Working: Cloning guild-operators into /tmp"
sudo rm -Rf /tmp/guild-operators && \
git clone -q https://github.com/cardano-community/guild-operators.git /tmp/guild-operators
cmdStatus "Success: Cloned guild-operators into /tmp"

sudo mkdir -p $grestConfigPath && \
sudo cp $scriptDir/files/grest.conf $grestConfigPath && \
sudo mv $grestConfigPath/grest.conf $grestConfigPath/main.conf && \
sudo sed -i "1 s/authenticator/$grestPostgresRole/" $grestConfigPath/main.conf && \
sudo sed -i "1 s/cexplorer/$grestPostgresDb/" $grestConfigPath/main.conf && \
sudo chown $grestSystemUser $grestConfigPath/main.conf && \
sudo chmod 0600 $grestConfigPath/main.conf
cmdStatus "Success: Installed $grestConfigPath/main.conf"

sqlBasics=$(cat /tmp/koios-artifacts/files/grest/rpc/db-scripts/basics.sql)
psql $grestPostgresDb -c "${sqlBasics//authenticator/"$grestPostgresRole"}" &>/dev/null
cmdStatus "Success: Created grest schemas in $grestPostgresDb"

if [[ $grestInstallPgBech32 -eq 1 ]];
then
    echo "Installing build tools, libbech32 and pg_bech32... "
    sudo apt install -y --no-install-recommends build-essential make g++ autoconf autoconf-archive automake libtool pkg-config postgresql-server-dev-all &>/dev/null
    cmdStatus "Success: Installed build tools"

    mkdir -p ~/src && rm -Rf ~/src/libbech32 && \
    git clone -q https://github.com/whitslack/libbech32.git ~/src/libbech32 && \
    cd ~/src/libbech32 && mkdir -p build-aux/m4 && \
    curl -sf https://raw.githubusercontent.com/NixOS/patchelf/master/m4/ax_cxx_compile_stdcxx.m4 -o build-aux/m4/ax_cxx_compile_stdcx.m4 && \
    autoreconf -i && ./configure >/dev/null && make >/dev/null && \
    sudo make install >/dev/null && sudo ldconfig >/dev/null
    cmdStatus "Success: Installed libbech32"

    rm -Rf ~/src/pg_bech32 && \
    git clone -q https://github.com/cardano-community/pg_bech32.git ~/src/pg_bech32 && \
    cd ~/src/pg_bech32 && make >/dev/null && sudo make install >/dev/null
    cmdStatus "Success: Installed pg_bech32"

    psql $grestPostgresDb -c "drop extension if exists pg_bech32" >/dev/null && \
    psql $grestPostgresDb -c "create extension pg_bech32" >/dev/null
    cmdStatus "Success: Created extension pg_bech_32"
fi

sudo mkdir -p $haProxyConfigPath && \
sudo cp $scriptDir/files/haproxy.conf $haProxyConfigPath && \
sudo mv $haProxyConfigPath/haproxy.conf $haProxyConfigPath/haproxy.cfg && \
sudo sed -i "s/GREST_USER/$grestSystemUser/" $haProxyConfigPath/haproxy.cfg && \
sudo sed -i "s,HAPROXY_CONFIG,$haProxyConfigPath," $haProxyConfigPath/haproxy.cfg && \
sudo sed -i "s,KOIOS_URL,$koiosUrl," $haProxyConfigPath/haproxy.cfg && \
sudo sed -i "s/127.0.0.1:1447/$ogmiosUrl/" $haProxyConfigPath/haproxy.cfg && \
sudo sed -i "s/127.0.0.1:8090/$submitApiUrl/" $haProxyConfigPath/haproxy.cfg
cmdStatus "Success: Installed $haProxyConfigPath/haproxy.cfg"

sudo mkdir -p $haProxyConfigPath/rpc && \
sudo curl -s https://api.koios.rest/koiosapi.yaml -o /tmp/koiosapi.yaml && \
grep "^  /" /tmp/koiosapi.yaml | grep -v -e submittx -e "#RPC" | sed -e 's#^  /#/#' | cut -d: -f1 | sort | sudo tee $haProxyConfigPath/rpc/grest &>/dev/null
echo "/control_table" | sudo tee $haProxyConfigPath/rpc/grest &>/dev/null
cmdStatus "Success: Installed $haProxyConfigPath/rpc/grest"

psql $grestPostgresDb < $scriptDir/files/genesis.sql 1>/dev/null
cmdStatus "Success: Populated grest.genesis from genesis.sql"

echo "Working: Importing RPC's into schema (this might take a while)..."
find /tmp/koios-artifacts/files/grest/rpc -name "*.sql" -type f -not -path "*db-scripts*" | sort | \
xargs -I {} psql $grestPostgresDb -v ON_ERROR_STOP=1 -c "set client_min_messages=ERROR" -f {} 1>/dev/null
cmdStatus "Success: Imported RPC's into schema"

psql $grestPostgresDb -c "grant select on all tables in schema public to $grestPostgresRole;" \
    -c "grant update on public.epoch to $grestPostgresRole;" \
    -c "grant truncate on grest.asset_info_cache to $grestPostgresRole;" \
    -c "grant select, insert, update, delete on all tables in schema grest to $grestPostgresRole;" \
    -c "grant execute on all functions in schema public to $grestPostgresRole;" \
    -c "grant execute on all functions in schema grest to $grestPostgresRole;" \
    -c "alter role $grestPostgresRole set statement_timeout=1200000;" 1>/dev/null
cmdStatus "Success: Set permissions on public and grest schemas"

echo "Working: Populating cache tables in grest schema (this might also take a while)..."
psql $grestPostgresDb -q -c "set client_min_messages to warning;" \
    -c "select grest.asset_info_cache_update();" \
    -c "select grest.epoch_info_cache_update();" \
    -c "select grest.active_stake_cache_update_check();" \
    -c "call grest.update_stake_distribution_cache();" \
    -c "select grest.pool_history_cache_update();" 1>/dev/null
cmdStatus "Success: Populated cache tables in grest schema"

sudo mkdir -p /usr/local/bin/koios && \
sudo cp /tmp/koios-artifacts/files/grest/cron/jobs/* /usr/local/bin/koios && \
sudo rm /usr/local/bin/koios/{asset-txo-cache-update,epoch-summary-corrections-update}.sh && \
find /usr/local/bin/koios/ -type f -exec sudo sed -i "s/^DB_NAME=.*/DB_CONNECT=\"$grestPostgresDb -U $grestPostgresRole\"/g" {} \; && \
find /usr/local/bin/koios/ -type f -exec sudo sed -i "s/DB_NAME/DB_CONNECT/g" {} \; && \
find /usr/local/bin/koios/ -type f -exec sudo sed -i "s/^CCLI=.*/CCLI=${cardanoCliPath//\//\\\/}/g" {} \; && \
find /usr/local/bin/koios/ -type f -exec sudo sed -i "s/^SOCKET=.*/SOCKET=${cardanoSocketPath//\//\\\/}/g" {} \; && \
find /usr/local/bin/koios/ -type f -exec sudo sed -i "s/^TR_DIR=.*/TR_DIR=\/tmp\nHOME=\/tmp/g" {} \; && \
find /usr/local/bin/koios/ -type f -exec sudo sed -i "s/^NWMAGIC=.*/NWMAGIC=764824073/g" {} \; && \
find /usr/local/bin/koios/ -type f -exec sudo sed -i "s/^PROM_URL=.*/PROM_URL=${cardanoMetricsUrl//\//\\\/}/g" {} \; && \
find /usr/local/bin/koios/ -type f -exec sudo sed -i "s/^EPOCH_LENGTH=.*/EPOCH_LENGTH=432000/g" {} \; && \
find /usr/local/bin/koios/ -type f -exec sudo sed -i "s/^export CARDANO_NODE_SOCKET_PATH=.*/export CARDANO_NODE_SOCKET_PATH=${cardanoSocketPath//\//\\\/}/g" {} \; && \
sudo cp $scriptDir/systemd/* /etc/systemd/system/ && \
sudo cp $scriptDir/files/get-metrics.sh /usr/local/bin/koios/get-metrics.sh && \
sudo sed -i "s/^\. .*/\. \/usr\/local\/bin\/koios\/\.env/" /usr/local/bin/koios/get-metrics.sh && \
sudo sed -i "s/^\#DBSYNC_PROM_HOST=.*/DBSYNC_PROM_HOST=\"${dbSyncMetricsAddr}\"/" /usr/local/bin/koios/get-metrics.sh && \
sudo sed -i "s/^\#DBSYNC_PROM_PORT=.*/DBSYNC_PROM_PORT=${dbSyncMetricsPort}/" /usr/local/bin/koios/get-metrics.sh && \
sudo sed -i "s/^\#PGDATABASE=.*/PGDATABASE=${grestPostgresDb}/" /usr/local/bin/koios/get-metrics.sh && \
sudo sed -i "s/^\#PGUSER=.*/PGUSER=${grestPostgresRole}/" /usr/local/bin/koios/get-metrics.sh && \
sudo sed -i "s/^\#NODE_PROM_URL=.*/NODE_PROM_URL=\"${cardanoMetricsUrl//\//\\\/}\"/" /usr/local/bin/koios/get-metrics.sh && \
sudo systemctl daemon-reload && sudo systemctl enable --now koios@{2,5,10,15,120}.timer grest-exporter.service &>/dev/null
cmdStatus "Success: Installed scripts and started systemd timers"

sudo systemctl restart postgrest haproxy
cmdStatus "Success: Restarted PostgREST and HAProxy"

echo "
Last but not least, please make sure that:

 - Ports 8053 (or 8453) for HAProxy and 8059 for grest-exporter.sh are opened on your firewall
 - PostgreSQL, DB-Sync, PostgREST, HAProxy, Submit-API and Ogmios are started and enabled
 - The command 'sudo -u $grestPostgresRole psql $grestPostgresDb' works (db-updates via systemd)
"
