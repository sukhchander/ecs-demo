#!/bin/bash

function usage(){
    echo "usage: $(basename $0)"
}

function key(){
    echo  ${1%%:*}
}
function value(){
    echo  ${1#*:}
}
function get(){
    KEY=$1
    shift
    for I in $@; do
  if [ $(key $I) = "$KEY" ]; then
      echo $(value $I)
      return
  fi
    done
}

if [ \( "$#" -gt 1 \) -o  \( "$1" = "--help" \) ]; then
    usage
    exit 1
fi

if [ -z "$(which aws)" ]; then
    echo "error: Cannot find AWS-CLI, please make sure it's installed"
    exit 1
fi

REGION=$(aws configure list 2> /dev/null | grep region | awk '{ print $2 }')
if [ -z "$REGION" ]; then
    echo "error: Region not set, please make sure to run 'aws configure'"
    exit 1
fi

ECS_AMIS=("us-east-1:ami-f66607e1", "us-west-1:ami-ffbbf99f", "us-west-2:ami-3dc2165d")
REGIONS=""
for I in ${ECS_AMIS[@]}; do
    REGIONS="$REGIONS $(key $I)"
done

AMI="$(get $REGION ${ECS_AMIS[@]})"
if [ -z "$AMI" ]; then
    echo "error: AWS-CLI is using '$REGION', which doesn't offer ECS yet, please set it to one from: ${REGIONS}"
    exit 1
fi

CLUSTER_STATUS=$(aws ecs describe-clusters --clusters ecs-demo-cluster --query 'clusters[0].status' --output text)
if [ "$CLUSTER_STATUS" != "None" -a "$CLUSTER_STATUS" != "INACTIVE" ]; then
    echo "error: ECS cluster ecs-demo-cluster is active, run teardown.sh first"
    exit 1
fi

set -euo pipefail

echo -n "Creating ECS cluster (ecs-demo-cluster) ... "
aws ecs create-cluster --cluster-name ecs-demo-cluster > /dev/null
echo "✔"

echo -n "Creating VPC (ecs-demo-vpc) ... "
VPC_ID=$(aws ec2 create-vpc --cidr-block 172.31.0.0/28 --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 create-tags --resources $VPC_ID --tag Key=Name,Value=ecs-demo-vpc
echo "✔"

echo -n "Creating Subnet (ecs-demo-subnet) ... "
SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.31.0.0/28 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SUBNET_ID --tag Key=Name,Value=ecs-demo-subnet
echo "✔"

# Internet Gateway
echo -n "Creating Internet Gateway (ecs-demo) ... "
GW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags --resources $GW_ID --tag Key=Name,Value=ecs-demo
aws ec2 attach-internet-gateway --internet-gateway-id $GW_ID --vpc-id $VPC_ID
TABLE_ID=$(aws ec2 describe-route-tables --query 'RouteTables[?VpcId==`'$VPC_ID'`].RouteTableId' --output text)
aws ec2 create-route --route-table-id $TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $GW_ID > /dev/null
echo "✔"

# Security group
echo -n "Creating Security Group (ecs-demo) ... "
SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name ecs-demo --vpc-id $VPC_ID --description 'ECS Demo' --query 'GroupId' --output text)
sleep 5
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 4040 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 6783 --source-group $SECURITY_GROUP_ID
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol udp --port 6783 --source-group $SECURITY_GROUP_ID
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol udp --port 6784 --source-group $SECURITY_GROUP_ID
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 4040 --source-group $SECURITY_GROUP_ID
echo "✔"

echo -n "Creating Key Pair (ecs-demo-key.pem) ... "
aws ec2 create-key-pair --key-name ecs-demo-key --query 'KeyMaterial' --output text > ecs-demo-key.pem
chmod 600 ecs-demo-key.pem
echo "✔"

echo -n "Creating IAM role (ecs-role) ... "
aws iam create-role --role-name ecs-role --assume-role-policy-document file://config/ecs-role.json > /dev/null
aws iam put-role-policy --role-name ecs-role --policy-name ecs-policy --policy-document file://config/ecs-policy.json
aws iam create-instance-profile --instance-profile-name ecs-instance-profile > /dev/null
while ! aws iam get-instance-profile --instance-profile-name ecs-instance-profile  2>&1 > /dev/null; do
    sleep 5
done
aws iam add-role-to-instance-profile --instance-profile-name ecs-instance-profile --role-name ecs-role
echo "✔"

echo -n "Creating Launch Configuration (ecs-launch-configuration) ... "
sleep 10

TMP_USER_DATA_FILE=$(mktemp /tmp/ecs-demo-user-data-XXXX)
trap 'rm $TMP_USER_DATA_FILE' EXIT
cp set-ecs-cluster-name.sh $TMP_USER_DATA_FILE
aws autoscaling create-launch-configuration --image-id $AMI --launch-configuration-name ecs-launch-configuration --key-name ecs-demo-key --security-groups $SECURITY_GROUP_ID --instance-type t2.micro --user-data file://$TMP_USER_DATA_FILE  --iam-instance-profile ecs-instance-profile --associate-public-ip-address --instance-monitoring Enabled=false
echo "✔"

echo -n "Creating Auto Scaling Group (ecs-demo-group) with 3 instances ... "
aws autoscaling create-auto-scaling-group --auto-scaling-group-name ecs-demo-group --launch-configuration-name ecs-launch-configuration --min-size 3 --max-size 3 --desired-capacity 3 --vpc-zone-identifier $SUBNET_ID
echo "✔"

echo -n "Waiting for instances to join the cluster (this may take a moment) ... "
while [ "$(aws ecs describe-clusters --clusters ecs-demo-cluster --query 'clusters[0].registeredContainerInstancesCount' --output text)" != 3 ]; do
    sleep 5
done
echo "✔"

echo -n "Registering ECS Task Definition (ecs-demo-task) ... "
aws ecs register-task-definition --family ecs-demo-task --container-definitions "$(cat config/ecs-demo-containers.json)" > /dev/null
echo "✔"

echo -n "Creating ECS Service with 3 tasks (ecs-demo-service) ... "
aws ecs create-service --cluster ecs-demo-cluster --service-name  ecs-demo-service --task-definition ecs-demo-task --desired-count 3 > /dev/null
echo "✔"

echo -n "Waiting for tasks to start running ... "
while [ "$(aws ecs describe-clusters --clusters ecs-demo-cluster --query 'clusters[0].runningTasksCount')" != 3 ]; do
    sleep 5
done
echo "✔"

INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ecs-demo-group --query 'AutoScalingGroups[0].Instances[*].InstanceId' --output text)
DNS_NAMES=$(aws ec2 describe-instances --instance-ids $INSTANCE_IDS --query 'Reservations[0].Instances[*].PublicDnsName' --output text)

echo "ECS cluster contains: "
for HOST in $DNS_NAMES; do
    echo "  http://$HOST"
done
echo "ECS cluster launched ... ✔"