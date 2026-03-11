#!/bin/bash

# CLOC
LOC_LIB=$(cloc ../lib --json | jq -r '.Elixir.code')
LOC_TEST=$(cloc ../test --json | jq -r '.Elixir.code')

# Replace old values
sed -i "s/\(<!-- LIB_COUNT -->\).*\(<!-- END_LIB_COUNT -->\)/\1$LOC_LIB\2/" ../README.md
sed -i "s/\(<!-- TEST_COUNT -->\).*\(<!-- END_TEST_COUNT -->\)/\1$LOC_TEST\2/" ../README.md
