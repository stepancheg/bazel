#!/bin/bash -eu
#
# Copyright 2016 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Tests the behavior of C++ rules.

# Load the test setup defined in the parent directory
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/../integration_test_setup.sh" \
  || { echo "integration_test_setup.sh not found!" >&2; exit 1; }

function test_extra_action_for_compile() {
  mkdir -p ea
  cat > ea/BUILD <<EOF
action_listener(
    name = "al",
    extra_actions = [":ea"],
    mnemonics = ["CppCompile"],
    visibility = ["//visibility:public"],
)

extra_action(
    name = "ea",
    cmd = "if ! [[ -r ea/cc.cc ]]; then echo 'source file not in inputs'; exit 1; fi",
)

cc_library(
    name = "cc",
    srcs = ["cc.cc"],
)
EOF

  echo 'void cc() {}' > ea/cc.cc

  bazel build --experimental_action_listener=//ea:al //ea:cc || fail "expected success"
}

function test_cc_library_include_prefix_external_repository() {
  r="$TEST_TMPDIR/r"
  mkdir -p "$TEST_TMPDIR/r/foo/v1"
  touch "$TEST_TMPDIR/r/WORKSPACE"
  echo "#define FOO 42" > "$TEST_TMPDIR/r/foo/v1/foo.h"
  cat > "$TEST_TMPDIR/r/foo/BUILD" <<EOF
cc_library(
  name = "foo",
  hdrs = ["v1/foo.h"],
  include_prefix = "foolib",
  strip_include_prefix = "v1",
  visibility = ["//visibility:public"],
)
EOF

  cat > WORKSPACE <<EOF
local_repository(
  name = "foo",
  path = "$TEST_TMPDIR/r",
)
EOF

  cat > BUILD <<EOF
cc_binary(
  name = "ok",
  srcs = ["ok.cc"],
  deps = ["@foo//foo"],
)

cc_binary(
  name = "bad",
  srcs = ["bad.cc"],
  deps = ["@foo//foo"],
)
EOF

  cat > ok.cc <<EOF
#include <stdio.h>
#include "foolib/foo.h"
int main() {
  printf("FOO is %d\n", FOO);
}
EOF

  cat > bad.cc <<EOF
#include <stdio.h>
#include "foo/v1/foo.h"
int main() {
  printf("FOO is %d\n", FOO);
}
EOF

  bazel build :bad && fail "Should not have found include at repository-relative path"
  bazel build :ok || fail "Should have found include at synthetic path"
}

# This test tests that Bazel can produce dynamic libraries that have undefined
# symbols on Mac and Linux. Not sure it is a sane default to allow undefined
# symbols, but it's the default we had historically. This test creates
# an executable (main) that defines bar(), and a shared library (plugin) that
# calls bar(). When linking the libplugin.so, symbol 'bar' is undefined.
#    +-----------------------------+     +----------------------------------+
#    |  main                       |     |  libplugin.so                    |
#    |                             |     |                                  |
#    |   main() { return foo(); } +---------> foo() { return bar() - 42; }  |
#    |                             |     |       +                          |
#    |                             |     |       |                          |
#    |   bar() { return 42; } <------------------+                          |
#    |                             |     |                                  |
#    +-----------------------------+     +----------------------------------+
function test_undefined_dynamic_lookup() {
  if is_windows; then
    # Windows doesn't allow undefined symbols in shared libraries.
    return 0
  fi
  mkdir -p "dynamic_lookup"
  cat > "dynamic_lookup/BUILD" <<EOF
cc_binary(
  name = "libplugin.so",
  srcs = ["plugin.cc"],
  linkshared = 1,
)

cc_binary(
    name = "main",
    srcs = ["main.cc", "libplugin.so"],
)
EOF

  cat > "dynamic_lookup/plugin.cc" <<EOF
int bar();
int foo() { return bar() - 42; }
EOF

  cat > "dynamic_lookup/main.cc" <<EOF
int foo();
int bar() { return 42; }
int main() { return foo(); }
EOF

  bazel build //dynamic_lookup:main || fail "Bazel couldn't build the binary."
  bazel run //dynamic_lookup:main || fail "Run of the binary failed."
}

run_suite "cc_integration_test"
