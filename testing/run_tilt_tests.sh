#/bin/bash

pgrep tilt > /dev/null
if [ $? -ne 0 ]; then
    echo "tilt is not running"
    exit 1;
fi

# start the offchain-relayer process
echo "Starting off-chain relayer process."
cd $(dirname $0)/../offchain-relayer && ./start-relayer.sh > offchain-relayer.out 2>&1 &

# go to the sdk directory
cd $(dirname $0)/../sdk

# run tests in sdk directory
npm run test

# kill the offchain-relayer process
pkill -f "exe/main relay"