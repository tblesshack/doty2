#!/bin/bash
# manager wrapper template: real manager passed through doty-linkfix
# install: mv /usr/local/bin/PROTO /usr/local/bin/PROTO.bin && cp this /usr/local/bin/PROTO
REAL=$(basename "$0")
exec /usr/local/bin/${REAL}.bin "$@" | /usr/local/bin/doty-linkfix
