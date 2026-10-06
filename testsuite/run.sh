#!/bin/sh
# SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

set -e
set -x
alr -C testsuite/ build -- -m -eS
alr -C testsuite/test_cases build -- -cargs -fcallgraph-info=su,da
alr -C testsuite/test_cases/ exec ../bin/testsuite
# Exit status contract of the munin executable. `alr exec` would collapse
# the child's status to 1, so import the environment instead.
set +x
eval "$(alr -C testsuite/test_cases printenv --unix)"
expect_status() {
    expected=$1
    shift
    set +e
    ../../bin/munin "$@" >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq "$expected" || {
        echo "expected exit $expected, got $status: munin $*"
        exit 1
    }
}
cd testsuite/test_cases
expect_status 1 check locks -P lock_check/lock_check.gpr
expect_status 0 check priorities -P callgraph_hello_world/callgraph_hello_world.gpr
expect_status 2 check locks -P does_not_exist.gpr
