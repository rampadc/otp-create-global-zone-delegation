#!/bin/bash

echo "---- Logging into provided managed cluster $managedClusterName ----"
clusterSecret=$(oc get clusterdeployment $managedClusterName -n $managedClusterName -o jsonpath='{.spec.clusterMetadata.adminPasswordSecretRef.name}')
username=$(oc get secret $clusterSecret  -n $managedClusterName -o jsonpath="{.data.username}" | base64 --decode)
password=$(oc get secret $clusterSecret  -n $managedClusterName -o jsonpath="{.data.password}" | base64 --decode)
apiURL=$(oc get clusterdeployment -n $managedClusterName -o jsonpath="{.items[0].status.apiURL}")

oc login $apiURL -u $username -p $password --insecure-skip-tls-verify

echo "---- Getting AWS ID and Key from managed cluster $managedClusterName ----"
export AWS_ACCESS_KEY_ID=$(oc get secret -n $managedClusterName $managedClusterName-aws-creds -o=jsonpath='{.data.aws_access_key_id}' | base64 --decode)
export AWS_SECRET_ACCESS_KEY=$(oc get secret -n $managedClusterName $managedClusterName-aws-creds -o=jsonpath='{.data.aws_secret_access_key}' | base64 --decode)
echo "Access key ID,Secret access key" >> creds.csv
echo "$AWS_ACCESS_KEY_ID,$AWS_SECRET_ACCESS_KEY" >> creds.csv

echo "Using access key $AWS_ACCESS_KEY_ID"
aws configure import --csv ./creds.csv

echo "---- Configuring route53 based on $managedClusterName's base domain ----"

# Run on an AWS managed cluster
export cluster_base_domain=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}')
echo "cluster_base_domain: $cluster_base_domain"

export cluster_zone_id=$(oc get dns cluster -o jsonpath='{.spec.publicZone.id}')
echo "cluster_zone_id: $cluster_zone_id"

export global_base_domain=global.${cluster_base_domain#*.}
echo "global_base_domain: $global_base_domain"

aws route53 create-hosted-zone --name ${global_base_domain} --caller-reference $(date +"%m-%d-%y-%H-%M-%S-%N")

export global_zone_res=$(aws route53 list-hosted-zones-by-name --dns-name ${global_base_domain} | jq -r .HostedZones[0].Id )
echo "global_zone_res: $global_zone_res"

export global_zone_id=${global_zone_res##*/}
echo "global_zone_id: $global_zone_id"

export delegation_record=$(aws route53 list-resource-record-sets --hosted-zone-id ${global_zone_id} | jq .ResourceRecordSets[0])
echo "delegation_record: $delegation_record"

envsubst < ./delegation-record.json > ./delegation-record.json
cat ./delegation-record.json

aws route53 change-resource-record-sets --hosted-zone-id ${cluster_zone_id} --change-batch ./delegation-record.json