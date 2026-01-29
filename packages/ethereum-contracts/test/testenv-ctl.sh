#!/usr/bin/env bash

# make sure that if any step fails, the script fails
set -xe

CMD=$1

start_hardhat_node() {
    npx hardhat node --port 47545
}

kill_hardhat_node() {
    pkill -f "hardhat node --port 47545" || true
}

if [ "$CMD" == "start" ];then
    kill_hardhat_node
    start_hardhat_node
elif [ "$CMD" == "stop" ];then
    kill_hardhat_node
fi
