#!/bin/bash

# Worker prefix:
worker_label=WORKER_LABEL

# Use the ephemeral drive as workspace:
cd /media/ephemeral0

# Install:
# - Ruby 1.9 (better multi-threading performance than Ruby 1.8)
# - lighttpd (HTTP server) for letting clients poll the instance status
# - ftp (FTP client) for uploading data to the cache EC2 instance
yum -y install ruby19
yum -y install lighttpd
yum -y install ftp

# Magic? No! It is for logging console output properly -- including output of this script!
exec > >(tee /var/www/lighttpd/log.txt|tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

service lighttpd start

# Configure wget to use the squid proxy on the "cache" EC2 instance:
grep -v -E '^((https?|ftp)_proxy|use_proxy)' /etc/wgetrc > wgetrc.tmp
cp wgetrc.tmp /etc/wgetrc
rm -f wgetrc.tmp
echo "https_proxy = http://CACHE_IP_VAR:3128/" >> /etc/wgetrc
echo "http_proxy = http://CACHE_IP_VAR:3128/" >> /etc/wgetrc
echo "ftp_proxy = http://CACHE_IP_VAR:3128/" >> /etc/wgetrc
echo "use_proxy = on" >> /etc/wgetrc

# Outputs should be put into this directory:
mkdir /media/ephemeral0/data

# Get the workflow software bundle:
mkdir /media/ephemeral0/workflow
cd /media/ephemeral0/workflow
wget http://CACHE_IP_VAR/bundle.tar
tar xf bundle.tar

# Execute the user's "worker" script:
source run_on_worker.sh

# Package and compress data for upload to the "cache" EC2 instance:
cd /media/ephemeral0
tar cf "data_${worker_label}.tar" -C "/media/ephemeral0/data" .

# Compress the tar file:
gzip "data_${worker_label}.tar"

# Uploads the packaged logs/results to the "cache" spot-instance:
ftp -n -v CACHE_IP_VAR << EOT
user anonymous x@y.z
prompt
cd uploads
binary
put data_${worker_label}.tar.gz
bye
bye
EOT

# Signal script completion:
echo "---EC2Workflow---worker-complete---(${worker_label})---"

# And now, terminate the instance:
halt

