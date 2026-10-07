#!/bin/sh
# Fake agent for the self-test: fails like an agent CLI without credentials.
# Prints a credential error, writes nothing, exits 1.
echo "Error getting AWS credentials from awsCredentialExport (in settings or ~/.claude.json): awsCredentialExport did not return a valid value" >&2
exit 1
