#!/usr/bin/env bash

# Overrides defaults of ec2workflow.sh

# Set labels for two "worker" EC2 instances (so, two EC2 instances will be started):
worker_labels=(one two)

# This is a toy example; picking very small instances is fine:
instance_type=m1.small

# Defaults are kept for the variables: "ami" and "zone"

