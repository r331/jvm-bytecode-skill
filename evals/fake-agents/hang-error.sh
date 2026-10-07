#!/bin/sh
# Fake agent for the self-test: prints a credential error and then hangs,
# like an agent CLI stuck after failing to get credentials.
echo "Error getting AWS credentials from awsCredentialExport (in settings or ~/.claude.json): awsCredentialExport did not return a valid value" >&2
sleep 600
