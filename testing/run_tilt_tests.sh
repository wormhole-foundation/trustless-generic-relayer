#/bin/bash

pgrep tilt > /dev/null
if [ $? -ne 0 ]; then
    echo "tilt is not running"
    exit 1;
fi

# go to the sdk directory
cd $(dirname $0)/../sdk

# run tests in sdk directory
npm run test