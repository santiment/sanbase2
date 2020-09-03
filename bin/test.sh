#!/bin/bash

if [ $# -eq 0 ]; then
  tests_to_execute="test"
else
  tests_to_execute="test $@"
fi

test_command="mix $tests_to_execute"

echo "Will execute: $test_command"


docker-compose run -e MIX_ENV=test sanbase sh -c "$test_command"
