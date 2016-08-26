#!/bin/bash

if [ -z "$(which aws)" ]; then
    echo "error: Cannot find AWS-CLI, please make sure it's installed"
    exit 1
fi

REGION=$(aws configure list 2> /dev/null | grep region | awk '{ print $2 }')
if [ -z "$REGION" ]; then
    echo "error: Region not set, please make sure to run 'aws configure'"
    exit 1
fi

if [ -n "$(aws ecs describe-clusters --clusters ecs-demo-cluster --query 'failures' --output text)" ]; then
    echo "error: ECS cluster ecs-demo-cluster doesn't exist, nothing to clean up"
    exit 1
fi

echo -n "Deleting ECS Service (ecs-demo-service) ... "
aws ecs update-service --cluster ecs-demo-cluster --service  ecs-demo-service --desired-count 0 > /dev/null
aws ecs delete-service --cluster ecs-demo-cluster --service  ecs-demo-service > /dev/null
echo "✔"

echo -n "De-registering ECS Task Definition (ecs-demo-task) ... "
REVISION=$(aws ecs describe-task-definition --task-definition ecs-demo-task --query 'taskDefinition.revision' --output text)
aws ecs deregister-task-definition --task-definition "ecs-demo-task:${REVISION}" > /dev/null
echo "✔"

echo -n "Deleting Auto Scaling Group (ecs-demo-group) ... "
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ecs-demo-group --query 'AutoScalingGroups[0].Instances[*].InstanceId' --output text)
aws autoscaling delete-auto-scaling-group --force-delete --auto-scaling-group-name ecs-demo-group
echo "✔"

echo -n "Waiting for instances to terminate (this may take a moment) ... "
STATE="run"
while [ -n "$STATE" -a "$STATE" != "terminated terminated terminated" ]; do
    STATE=$(aws ec2 describe-instances --instance-ids ${INSTANCE_IDS} --query 'Reservations[0].Instances[*].State.Name' --output text)
    STATE=$(echo $STATE)
    sleep 2
done
echo "✔"

echo -n "Deleting Launch Configuration (ecs-launch-configuration) ... "
aws autoscaling delete-launch-configuration --launch-configuration-name ecs-launch-configuration
echo "✔"

echo -n "Deleting ecs-role IAM role (ecs-role) ... "
aws iam remove-role-from-instance-profile --instance-profile-name ecs-instance-profile --role-name ecs-role
aws iam delete-instance-profile --instance-profile-name ecs-instance-profile
aws iam delete-role-policy --role-name ecs-role --policy-name ecs-policy
aws iam delete-role --role-name ecs-role
echo "✔"

echo -n "Deleting Key Pair (ecs-demo-key, deleting file ecs-demo-key.pem) ... "
aws ec2 delete-key-pair --key-name ecs-demo-key
rm -f ecs-demo-key.pem
echo "✔"

echo -n "Deleting Security Group (ecs-demo) ... "
GROUP_ID=$(aws ec2 describe-security-groups --query 'SecurityGroups[?GroupName==`ecs-demo`].GroupId' --output text)
aws ec2 delete-security-group --group-id "$GROUP_ID"
echo "✔"

echo -n "Deleting Internet gateway ... "
VPC_ID=$(aws ec2 describe-tags --filters Name=resource-type,Values=vpc,Name=tag:Name,Values=ecs-demo-vpc --query 'Tags[0].ResourceId' --output text)
GW_ID=$(aws ec2 describe-tags --filters Name=resource-type,Values=internet-gateway,Name=tag:Name,Values=ecs-demo --query 'Tags[0].ResourceId' --output text)
aws ec2 detach-internet-gateway --internet-gateway-id $GW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $GW_ID
echo "✔"

echo -n "Deleting Subnet (ecs-demo-subnet) ... "
SUBNET_ID=$(aws ec2 describe-tags --filters Name=resource-type,Values=subnet,Name=tag:Name,Values=ecs-demo-subnet --query 'Tags[0].ResourceId' --output text)
aws ec2 delete-subnet --subnet-id $SUBNET_ID
echo "✔"

echo -n "Deleting VPC (ecs-demo-vpc) ... "
aws ec2 delete-vpc --vpc-id $VPC_ID
echo "✔"

echo -n "Deleting ECS cluster (ecs-demo-cluster) ... "
aws ecs delete-cluster --cluster ecs-demo-cluster > /dev/null
echo "✔"