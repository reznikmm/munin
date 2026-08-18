#!/bin/sh
# SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

set -e
set -x
alr -C testsuite/ build -- -m -eS
alr -C testsuite/test_cases build -- -cargs -fcallgraph-info=su,da
alr -C testsuite/test_cases/ exec ../bin/testsuite