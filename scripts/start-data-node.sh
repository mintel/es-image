#!/bin/bash
set -e

python /manage-es.py persitent-settings
python /manage-es.py post-start-data
