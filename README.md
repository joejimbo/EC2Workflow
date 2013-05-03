EC2Workflow
-----------

EC2Workflow is a workflow for executing data mining pipelines on Amazon's Elastic Compute Cloud (Amazon EC2).

This implementation is a generalization of the text mining pipeline used in [opacmo](http://www.opacmo.org).

### Schematic

![opacmo logo](https://github.com/joejimbo/opacmo/raw/master/images/workflow.png)

### Usage

Command line: `ec2workflow.sh instance_type workflow_directory`

Options for _instance\_type_:

*  `ondemand`: use on-demand instances (fixed price, guaranteed availability once started)
*  `spot`: use spot instances (variable price, availability not guaranteed)

Contents of _workflow\_directory_:
* `configuration.sh` : override default variables (if needed) that are otherwise set to default values; this file is optional
*  `run\_on\_cache.sh`  : executed on the "cache" EC2 instance; should be used for downloading data that gets deposited in the cache; this file is mandatory
*  `run\_on\_worker.sh` : executed on the "worker" EC2 instances; should be used to process data (download/upload of data from/to the "cache" EC2 instance is automated); this file is mandatory
*  other files: will be transferred too, but not be executed automatically

### Example

First, you need to install Amazon's EC2 API tools (the tools' version number might be different for you):

    wget 'http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip'
    unzip ec2-api-tools.zip
    export PATH=$PATH:`pwd`/ec2-api-tools-1.6.7.2/bin
    export EC2_HOME=`pwd`/ec2-api-tools-1.6.7.2
    # See: https://portal.aws.amazon.com/gp/aws/securityCredentials
    # AWS_ACCOUNT_ID looks like '1234-5678-9012'
    # AWS_ACCESS_KEY looks like 'BUE920...', 20 characters
    # AWS_SECRET_KEY looks like 'EsfW2R...', >20 characters
    export AWS_ACCOUNT_ID=...
     export AWS_ACCESS_KEY=...
    export AWS_SECRET_KEY=...

Second, you install EC2Workflow:

    git clone git://github.com/joejimbo/EC2Workflow.git
    cd EC2Workflow
    git checkout v1.0.0
    export PATH=$PATH:`pwd`

Now EC2Workflow is ready for use. Try to run the small example that comes with it (costs a few cents):

    ec2workflow.sh ondemand ~/src/EC2Workflow/example

The console output will look like this:

    Creating 'ec2workflow_12345678_123456' key pair...
    ...
    Your workflow is now being executed.
    
    "cache" EC2 instance identifier : i-e1234567
    "cache" EC2 instance IP address : 1.2.3.4

Once the EC2Workflow script completed its execution, watch your Amazon EC2 console until only the "cache" EC2 instance is still running. This should be almost instantly the case for this toy example. Then you can proceed to move the data off the cloud:

    scp -i ec2workflow_12345678_123456.pem ec2-user@1.2.3.4:/media/ephemeral0/ftp/uploads/* .

Finally, terminate the "cache" EC2 instance too, wait, then delete the security group it was using too:

    ec2-terminate-instances i-e1234567
    ec2-delete-group ec2workflow_12345678_123456

### License

This software is release under the [MIT license](https://raw.github.com/joejimbo/EC2Workflow/master/LICENSE).

