#!/usr/bin/env bash

# This script runs on the "cache" EC2 instance. Downloads should be
# made here, which populate the cache of the FTP/HTTP/HTTPS proxy.

# Download Wikipedia page "Amazon EC2":
wget http://en.wikipedia.org/wiki/Amazon_ec2

# ...done. The document is cached in the proxy now. This works also for
# very large files, such as .tar.gz, .zip, etc., and other files.

