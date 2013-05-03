#!/usr/bin/env bash

# This script is being run on "worker" EC2 instances.

# Download Wikipedia page "Amazon EC2", again, but this copy is
# being retrieved from the "cache" EC2 instance. That means that
# you are not charged for re-downloading this file from outside
# the AWS network, BUT MORE IMPORTANTLY, YOU WILL NOT GET YOURSELF
# BLOCKED BECAUSE YOUR ARE DOWNLOADING DATA N-TIMES SIMULTANEOUSLY
# (depending on your configuration.sh).
wget http://en.wikipedia.org/wiki/Amazon_ec2

# The actual "work" can now be carried out:
#   1. jot down the label of this "worker"
#   2. count the number of lines in the HTML file

data_directory=/media/ephemeral0/data

echo "Worker label: $worker_label" > $data_directory/example_data
wc -l Amazon_ec2 >> $data_directory/example_data

# To make debugging easier, also include the console log
# in the data directory. The file will then be downloaded
# alongside the data.
cp /var/log/user-data.log $data_directory


