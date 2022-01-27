#!/bin/bash

# Disable AWS Pagination
export AWS_PAGER=""

echo "---- Getting AWS ID and Key for managed cluster $managedClusterName ----"
echo "------ Using AWS user $AWS_USER ------"
export AWS_ACCESS_KEY_ID=$(oc get secret -n $managedClusterName $managedClusterName-aws-creds -o=jsonpath='{.data.aws_access_key_id}' | base64 --decode)
export AWS_SECRET_ACCESS_KEY=$(oc get secret -n $managedClusterName $managedClusterName-aws-creds -o=jsonpath='{.data.aws_secret_access_key}' | base64 --decode)
rm -f creds.csv
echo "User Name,Access key ID,Secret access key" >> creds.csv
echo "$AWS_USER,$AWS_ACCESS_KEY_ID,$AWS_SECRET_ACCESS_KEY" >> creds.csv

aws configure import --csv file://creds.csv

echo "---- Configuring route53 based on $managedClusterName's base domain ----"

echo "---- Logging into provided managed cluster $managedClusterName ----"
clusterSecret=$(oc get clusterdeployment $managedClusterName -n $managedClusterName -o jsonpath='{.spec.clusterMetadata.adminPasswordSecretRef.name}')
username=$(oc get secret $clusterSecret  -n $managedClusterName -o jsonpath="{.data.username}" | base64 --decode)
password=$(oc get secret $clusterSecret  -n $managedClusterName -o jsonpath="{.data.password}" | base64 --decode)
apiURL=$(oc get clusterdeployment -n $managedClusterName -o jsonpath="{.items[0].status.apiURL}")

oc login $apiURL -u $username -p $password --insecure-skip-tls-verify

# Run on an AWS managed cluster
export cluster_base_domain=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
echo "cluster_base_domain: $cluster_base_domain"

export cluster_zone_id=$(oc get dns cluster -o jsonpath='{.spec.publicZone.id}')
echo "cluster_zone_id: $cluster_zone_id"

export global_base_domain=global.${cluster_base_domain#*.}
echo "global_base_domain: $global_base_domain"

export RESULT=$(aws route53 list-hosted-zones-by-name --dns-name ${global_base_domain} --profile $AWS_USER | jq '.HostedZones | length')
if [ $RESULT -eq 0 ]; then
  echo "$global_base_domain does not exist."
else
  echo "$global_base_domain already exists. Deleting..."
  export global_zone_res=$(aws route53 list-hosted-zones-by-name --dns-name ${global_base_domain} --profile $AWS_USER | jq -r '.HostedZones[0].Id')
  export global_zone_id=${global_zone_res##*/}
  aws route53 delete-hosted-zone --id $global_zone_id --profile $AWS_USER
fi

# Wait for global zone is deleted before creating in case this app is run multiple times
export RESULT=$(aws route53 list-hosted-zones-by-name --dns-name ${global_base_domain} --profile $AWS_USER | jq '.HostedZones | length')
while [ $RESULT -ne 0 ]; do
  export RESULT=$(aws route53 list-hosted-zones-by-name --dns-name ${global_base_domain} --profile $AWS_USER | jq '.HostedZones | length')
done

echo "Creating $global_base_domain hosted zone."
aws route53 create-hosted-zone --name ${global_base_domain} --caller-reference $(date +"%m-%d-%y-%H-%M-%S-%N") --profile $AWS_USER

export global_zone_res=$(aws route53 list-hosted-zones-by-name --dns-name ${global_base_domain} --profile $AWS_USER | jq -r '.HostedZones[0].Id')
echo "global_zone_res: $global_zone_res"

export global_zone_id=${global_zone_res##*/}
echo "global_zone_id: $global_zone_id"

export delegation_record=$(aws route53 list-resource-record-sets --hosted-zone-id ${global_zone_id} --profile $AWS_USER | jq -r '.ResourceRecordSets[0]')
echo "delegation_record: $delegation_record"
#
envsubst < ./delegation-record.json > ./delegation-record-envsubst.json
cat ./delegation-record-envsubst.json | jq

aws route53 change-resource-record-sets --hosted-zone-id ${cluster_zone_id} --change-batch file://delegation-record-envsubst.json --profile $AWS_USER