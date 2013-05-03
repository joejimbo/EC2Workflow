#!/usr/bin/env bash

# ec2workflow:
#
# A BASH script for initiating a self directed (automatic/autonomous)
# workflow on multiple EC2 instances. There will be one EC2 instance
# that acts as a "cache" and multiple instances acting as "workers".
#
# The "cache" instance downloads supplemental files for the workers
# and also stores the final processing results of finished worker
# instances.
#
# A "worker" instance downloads files from the "cache" instance, and
# upon processing completion, deposits the results with the "cache"
# instance before terminating.

#
# AWS EC2 CONFIGURATION
#

# Labels for distinguishing data coming from various worker instances:
worker_labels=(worker1 worker2 worker3)

# AWS EC2 AMI to use (has to be a Linux AMI from Amazon; others Linux AMIs might work too though):
ami=ami-1624987f

# AWS EC2 instance type (needs to be a type that comes with ephemeral storage):
instance_type=m2.2xlarge

# AWS EC2 zone in which the instances will be created:
# Note that availability zones are different for each account, which means that
# picking a fixed zone here does not imply that the same physical zone is used
# across different user accounts.
# (see http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html)
zone=us-east-1a

#
# SCRIPT SPECIFIC SETTINGS (best not meddled with)
#

# Number of seconds to wait between checks whether the "cache" spot-instance is up:
SPOT_CHECK_INTERVAL=20

# Number of seconds to wait between checks whether the "cache" instance's interfaces have IPs yet:
IP_WAIT=5

# Number of seconds to wait between checks whether the "cache" instance is setup and done downloading:
CACHE_SETUP_INTERVAL=10
CACHE_CHECK_INTERVAL=20

# Number of seconds to wait after creating a security group:
POST_SECURITY_GROUP_WAIT=3

#
# ACTUAL SCRIPT
#

# Determine OS this script is executed on:
os=`uname`
if [ "$os" != 'Darwin' ] && [ "$os" != 'Linux' ] ; then
	echo "Sorry, but you have to run this script under Mac OS X or Linux."
	exit 1
fi

# Set sed/awk depending on the OS:
#   Use 'gawk' as default. Mac OS X's 'awk' works as well, but
#   for consistency I would suggest running `sudo port install gawk`.
#   The default Linux 'awk' does *not* work.
if [ "$os" = 'Darwin' ] ; then
	awk_interpreter=awk
	sed_regexp=-E
fi
if [ "$os" = 'Linux' ] ; then
	awk_interpreter=gawk
	sed_regexp=-r
fi

# This function looks for a given phrase (param 1) to occur in the log-file
# of the cache instance. If it does not occur, wait a number of seconds (param 2)
# and then re-check.
wait_for_completion() {
	COMPLETE=0
	while [ "$COMPLETE" = '0' ] ; do
		echo -n '.'
		sleep $2
		COMPLETE=`wget -q -O - http://$PUBLIC_CACHE_IP/log.txt | grep -o $1 | wc -l | tr -d ' '`
	done
	echo ''
}

# This function prints out whether a specific program is installed on the system (or not).
check_program() {
  if [ "`which $1`" != '' ] ; then
    echo 'ok'
  else
    echo 'missing or not in $PATH'
  fi
}

prerequisites_message() {
  echo "Sorry, it seems you do not have the necessary software requirement on your system:"
  echo ""
  if [ "$awk_interpreter" = 'awk' ] ; then
    awk_interpreter='awk '
  fi
  echo -n "  $awk_interpreter                            : "
  check_program "$awk_interpreter"
  echo -n "  bc                              : "
  check_program 'bc'
  echo -n "  ec2-authorize                   : "
  check_program 'ec2-authorize'
  echo -n "  ec2-create-group                : "
  check_program 'ec2-create-group'
  echo -n "  ec2-create-keypair              : "
  check_program 'ec2-create-keypair'
  echo -n "  ec2-describe-instances          : "
  check_program 'ec2-describe-instances'
  echo -n "  ec2-describe-spot-price-history : "
  check_program 'ec2-describe-spot-price-history'
  echo -n "  ec2-request-spot-instances      : "
  check_program 'ec2-request-spot-instances'
  echo -n "  ec2-run-instances               : "
  check_program 'ec2-run-instances'
  echo -n "  ec2workflow.sh                  : "
  check_program 'ec2workflow.sh'
  echo -n "  sed                             : "
  check_program 'sed'
  echo -n "  tar                             : "
  check_program 'tar'
  echo -n "  wget                            : "
  check_program 'wget'
}

help_message() {
	echo "Usage: ec2workflow.sh instance_type workflow_directory"
	echo ""
	echo "Kicks off a self guided workflow on a number of EC2 instances. More information,"
  echo "documentation and an example can be found here: https://github.com/joejimbo/EC2Workflow"
  echo ""
	echo "Options for 'instance_type':"
	echo "  ondemand : use on-demand instances (fixed price, guaranteed availability once started)"
	echo "  spot     : use spot instances (variable price, availability not guaranteed)"
  echo ""
  echo "Contents of 'workflow_directory':"
  echo "  configuration.sh : override default variables (if needed) that are otherwise set"
  echo "                     to default values; this file is optional"
  echo "                     Variable \"worker_labels\"        : (${worker_labels[@]})"
  echo "                     Variable \"ami\"                  : $ami"
  echo "                     Variable \"instance_type\"        : $instance_type"
  echo "                     Variable \"zone\"                 : $zone"
  echo "  run_on_cache.sh  : executed on the \"cache\" EC2 instance; should be used for"
  echo "                     downloading data that gets deposited in the cache; this file"
  echo "                     is mandatory"
  echo "                     Working directory                 : /media/ephemeral0/workflow"
  echo "                     \"worker\" upload directory       : /media/ephemeral0/ftp/uploads"
  echo "  run_on_worker.sh : executed on the \"worker\" EC2 instances; should be used to"
  echo "                     process data (download/upload of data from/to the \"cache\""
  echo "                     EC2 instance is automated); this file is mandatory"
  echo "                     Working directory                 : /media/ephemeral0/workflow"
  echo "                     Directory for upload to \"cache\" : /media/ephemeral0/data"
  echo "  other files      : will be transferred too, but not be executed automatically"
  echo ""
  echo "This software is release under the MIT license."
  echo "(https://raw.github.com/joejimbo/EC2Workflow/master/LICENSE)"
}

# Check software prerequisites:
if [[ $(check_program "$awk_interpreter") != 'ok' ||
      $(check_program 'bc') != 'ok' ||
      $(check_program 'ec2-authorize') != 'ok' ||
      $(check_program 'ec2-create-group') != 'ok' ||
      $(check_program 'ec2-create-keypair') != 'ok' ||
      $(check_program 'ec2-describe-instances') != 'ok' ||
      $(check_program 'ec2-describe-spot-price-history') != 'ok' ||
      $(check_program 'ec2-request-spot-instances') != 'ok' ||
      $(check_program 'ec2-run-instances') != 'ok' ||
      $(check_program 'ec2workflow.sh') != 'ok' ||
      $(check_program 'sed') != 'ok' ||
      $(check_program 'tar') != 'ok' ||
      $(check_program 'wget') != 'ok' ]] ; then
  prerequisites_message
  exit 2
fi

# If there are not exactly two arguments provided, print help message and exit:
if [[ ! $# -eq 2 ]] ; then
	help_message
	exit 2
fi

# If the first argument provided is not a known option, print help message and exit:
if [ "$1" != 'ondemand' ] && [ "$1" != 'spot' ] ; then
  echo "First parameter argument unknown."
  echo ""
	help_message
	exit 2
fi

# If the second argument provided is not a directory, print help message and exit:
if [ ! -d "$2" ] ; then
  echo "Second parameter argument is not a directory."
  echo ""
  help_message
  exit 2
fi

# See whether mandatory user scripts have been provided:
for script in {run_on_cache.sh,run_on_worker.sh} ; do
  if [ ! -f "$2/$script" ] ; then
    echo "The file \"run_on_cache.sh\" is not present in the workflow directory."
    echo ""
    help_message
    exit 2
  fi
done

base=`which ec2workflow.sh`
base=`dirname $base`

# Make sure that the bootstrap scripts are present:
if [ ! -f "$base/bootstrap/cache.sh" ] || [ ! -f "$base/bootstrap/worker.sh" ] ; then
  echo "Woops. Cannot locate the bootstrap scripts (cache.sh/worker.sh)."
  echo "Is \"ec2workflow.sh\" in \$PATH the script from the Github repository?"
  exit 2
fi

# Almost there... make sure all AWS variables are set:
if [ "$EC2_HOME" = '' ] ; then
  echo "The variable \$EC2_HOME is not set."
  echo ""
  help_message
  exit 2
fi
if [ "$AWS_ACCOUNT_ID" = '' ] ; then
  echo "The variable \$AWS_ACCOUNT_ID is not set."
  echo ""
  help_message
  exit 2
fi
if [ "$AWS_ACCESS_KEY" = '' ] ; then
  echo "The variable \$AWS_ACCESS_KEY is not set."
  echo ""
  help_message
  exit 2
fi
if [ "$AWS_SECRET_KEY" = '' ] ; then
  echo "The variable \$AWS_SECRET_KEY is not set."
  echo ""
  help_message
  exit 2
fi

pricing=$1
workflow=$2

# If a configuration script is provided, then run it here:
if [ -f "$workflow/configuration.sh" ] ; then
  source "$workflow/configuration.sh"
fi

# This time stamp is used to create unique-ish names:
TIMESTAMP=`date +%Y%m%d_%H%M%S`

# Create a temporary directoy for intermediate outputs:
tmpdir=/tmp/ec2workflow_$TIMESTAMP
mkdir $tmpdir

# If spot instances should be used, then determine an upper price boundary here:
if [ "$pricing" = 'spot' ] ; then
	# Determine suitable price:
	N=0
	FACTOR=1.5
	AVG_PRICE=0.0
	ec2-describe-spot-price-history -t $instance_type --product-description 'Linux/UNIX' | cut -f 2 -d '	' | sort -n > $tmpdir/aws_prices.tmp
	for price in `cat $tmpdir/aws_prices.tmp` ; do
		AVG_PRICE=`echo "$AVG_PRICE+$price" | bc`
		let N=N+1
	done
	MEDIAN_PRICE=`$awk_interpreter '{ count[NR] = $1; } END { if (NR % 2) { print count[(NR + 1) / 2]; } else { print (count[(NR / 2)] + count[(NR / 2) + 1]) / 2.0; } }' $tmpdir/aws_prices.tmp`
	MEDIAN_PRICE=`echo "scale=3;$MEDIAN_PRICE/1" | bc | sed $sed_regexp 's/^\./0./'`
	AVG_PRICE=`echo "scale=3;$AVG_PRICE/$N" | bc | sed $sed_regexp 's/^\./0./'`
	MAX_PRICE=`echo "scale=3;$MEDIAN_PRICE*$FACTOR" | bc | sed $sed_regexp 's/^\./0./'`
	rm -f $tmpdir/aws_prices.tmp

	echo "Over $N reported prices, all zones (via 'ec2-describe-spot-price-history'):"
	echo "Average price: $AVG_PRICE"
	echo "Median price: $MEDIAN_PRICE"
	echo ""
	echo "Suggest max. price for workflow run: $MAX_PRICE (${FACTOR}x median price)"

	echo -n "Type 'yes' (without the quotes) to accept, or enter a max. price (e.g., 0.70): "
	read user_agreement_or_price

	if [ "$user_agreement_or_price" != 'yes' ] ; then
		if [ "`echo -n "$user_agreement_or_price" | grep -o -E '^[0-9]+\.[0-9]+$'`" != "$user_agreement_or_price\n" ] ; then
			MAX_PRICE=$user_agreement_or_price
			echo -n "Type 'yes' to accept your custom price of $MAX_PRICE and continue: "
			read user_agreement
			if [ "$user_agreement" != 'yes' ] ; then
				echo 'You declined your suggested price. Aborting.'
				exit 3
			fi
		else
			echo 'You declined the suggested price. Aborting.'
			exit 4
		fi
	fi
fi

# Create key pair for accessing cache/worker instances:
echo "Creating 'ec2workflow_$TIMESTAMP' key pair..."
ec2-create-keypair ec2workflow_$TIMESTAMP | sed '1d' > ec2workflow_$TIMESTAMP.pem
chmod 600 ec2workflow_$TIMESTAMP.pem
export AWS_KEY_PAIR=ec2workflow_$TIMESTAMP

# Create a security group that determines open/closed ports per protocol:
echo "Setting up 'ec2workflow_$TIMESTAMP' security group..."
SECURITY_GROUP=`ec2-create-group --description 'ec2workflow security group' ec2workflow_$TIMESTAMP | cut -f 2 -d '	'`
if [ "$SECURITY_GROUP" = '' ] ; then
	echo "Could not create the security group 'ec2workflow_$TIMESTAMP' (via ec2-create-group). Does it already exist?"
	exit 5
fi
echo "Security group 'ec2workflow_$TIMESTAMP' created: $SECURITY_GROUP"
sleep $POST_SECURITY_GROUP_WAIT
ec2-authorize $SECURITY_GROUP -p 22
ec2-authorize $SECURITY_GROUP -p 80
ec2-authorize $SECURITY_GROUP -o $SECURITY_GROUP -u $AWS_ACCOUNT_ID

# If spot instances should be used, then start the "cache" here:
if [ "$pricing" = 'spot' ] ; then
	echo "Requesting spot instance (via ec2-request-spot-instances)..."
	SPOT_INSTANCE_REQUEST=`ec2-request-spot-instances -g ec2workflow_$TIMESTAMP -p $MAX_PRICE -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file $base/bootstrap/cache.sh $ami | grep -E 'sir-.+' | cut -f 2 -d '	'`
	echo "Spot instance request filed: $SPOT_INSTANCE_REQUEST"

	echo -n "Waiting for instance to boot."
	INSTANCE=
	while [ "$INSTANCE" = '' ] ; do
		echo -n '.'
		sleep $SPOT_CHECK_INTERVAL
		INSTANCE=`ec2-describe-spot-instance-requests $SPOT_INSTANCE_REQUEST | cut -f 12 -d '	'`
	done
	echo ''
fi

# If on-demand instances should be used, then start the "cache" here:
if [ "$pricing" = 'ondemand' ] ; then
	echo "Requesting on-demand instance (via ec2-run-instances)..."
	INSTANCE=`ec2-run-instances --instance-initiated-shutdown-behavior terminate -g ec2workflow_$TIMESTAMP -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file $base/bootstrap/cache.sh $ami | tail -n+2 | cut -f 2 -d '	'`
fi

# Get IPs of the cache instance:
echo "Instance started: $INSTANCE"
echo -n "Getting IP addresses."
PUBLIC_CACHE_IP=
while [ "$PUBLIC_CACHE_IP" = '' -o "$PRIVATE_CACHE_IP" = '' ] ; do
	echo -n '.'
	sleep $IP_WAIT
	PUBLIC_CACHE_IP=`ec2-describe-instances $INSTANCE | grep -E "	$INSTANCE	" | cut -f 17 -d '	'`
	PRIVATE_CACHE_IP=`ec2-describe-instances $INSTANCE | grep -E "	$INSTANCE	" | cut -f 18 -d '	'`
done
echo ''
echo "External IP: $PUBLIC_CACHE_IP"
echo "Internal IP: $PRIVATE_CACHE_IP"

echo -n "Waiting for instance setup completion."
wait_for_completion '\-\-\-EC2Workflow\-\-\-setup\-complete\-\-\-' $CACHE_SETUP_INTERVAL

# Setup the cache instance, initiate downloads, etc.:
echo 'Moving workflow bundle to the cache instance...'
tar cf $tmpdir/bundle.tar -C "$workflow" .
scp -i ec2workflow_$TIMESTAMP.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $tmpdir/bundle.tar ec2-user@$PUBLIC_CACHE_IP:/var/www/lighttpd
echo "Bundle has been transferred." > $tmpdir/bundle_transferred.tmp
scp -i ec2workflow_$TIMESTAMP.pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $tmpdir/bundle_transferred.tmp ec2-user@$PUBLIC_CACHE_IP:/var/www/lighttpd
rm -f $tmpdir/bundle.tar $tmpdir/bundle_transferred.tmp

echo -n "Waiting for instance to run and complete \"run_on_cache.sh\"."
wait_for_completion '\-\-\-EC2Workflow\-\-\-cache\-complete\-\-\-' $CACHE_CHECK_INTERVAL

# Start the "workers" -- note that these will terminate when they finish their data processing successfully:
echo "Starting worker instances..."
for worker_label in ${worker_labels[@]} ; do
	echo "Starting worker for journal worker_label: $worker_label"
	sed $sed_regexp "s/WORKER_LABEL/$worker_label/g" $base/bootstrap/worker.sh | sed $sed_regexp "s/CACHE_IP_VAR/$PRIVATE_CACHE_IP/g" > $tmpdir/worker_$worker_label.sh

	if [ "$pricing" = 'spot' ] ; then
		ec2-request-spot-instances -g ec2workflow_$TIMESTAMP -p $MAX_PRICE -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file $tmpdir/worker_$worker_label.sh $ami
	fi

	if [ "$pricing" = 'ondemand' ] ; then
		ec2-run-instances --instance-initiated-shutdown-behavior terminate -g ec2workflow_$TIMESTAMP -k $AWS_KEY_PAIR -z $zone -t $instance_type -b '/dev/sda2=ephemeral0' --user-data-file $tmpdir/worker_$worker_label.sh $ami
	fi
done

rm -rf $tmpdir

echo ""
echo "Your workflow is now being executed."
echo ""
echo "\"cache\" EC2 instance identifier : $INSTANCE"
echo "\"cache\" EC2 instance IP address : $PUBLIC_CACHE_IP"

