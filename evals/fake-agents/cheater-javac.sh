#!/bin/sh
# Fake agent for the self-test: tries to use the Java compiler.
cd "${WORKDIR:?}"
javac -version
exit 0
