#!/bin/bash

echo "Setting up Spark environment variables..."

# Create Spark logs directory
mkdir -p /opt/spark/logs

# Set Spark environment variables
export SPARK_LOCAL_IP=127.0.0.1
export SPARK_MASTER_HOST=127.0.0.1

echo "Local Spark setup complete."
