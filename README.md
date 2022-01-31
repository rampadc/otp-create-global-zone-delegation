# Create Global Zone Delegation job for AWS

This job sets up a global zone with AWS Route53 using the base domain for one of the AWS managed cluster.
Internally, it runs `main.sh` script, accepting the following environment variables:

- `managedClusterName`: name of the managed cluster to log into to get base domain
- `AWS_USER`: IAM user for AWS

To use this job, use the image output at `quay.io/congxdev/okd48cli-awscli:latest`.

### Prerequisites

This job is meant to run on an OpenShift cluster with Red Hat Advanced Cluster Management (RHACM) installed.
In RHACM, a managed cluster hosted on AWS with credentials available in the hub cluster's namespace.

