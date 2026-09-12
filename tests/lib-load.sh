#!/bin/sh
BATON_RELEASE_ROOT=$ROOT
BATON_LIB=$ROOT/lib
for test_lib in lock log git adapter plan templates derive runs dispatch integrate inbox status; do . "$BATON_LIB/$test_lib.sh"; done
