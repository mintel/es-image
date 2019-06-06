#!/bin/bash
set -e

# Perform a Sync to persistent storage
sync 

python /manage-es.py pre-stop-data
