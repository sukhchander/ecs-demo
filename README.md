## AWS ECS Demo


## Requirements

* [AWS CLI](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html)
* [Amazon EC2](https://aws.amazon.com/ec2/)
* [Docker](https://www.docker.com/aws)
* [Amazon ECS](http://aws.amazon.com/ecs/)
* [Amazon ECS Agent](https://github.com/aws/amazon-ecs-agent) manages containers with Amazon ECS.


## Clone

~~~ bash
git clone https://github.com/sukhchander/ecs-demo
cd ecs-demo
~~~

## AWS CLI

Ensure AWS CLI is set to use a region where Amazon ECS is available ie:
(`us-east-1`, `us-west1`, `us-west-2`)

view:

~~~bash
aws configure list
~~~

modify:

~~~bash
aws configure
~~~


## Setup and Configuration

Run the following command:

~~~bash
./setup.sh
~~~

Output:

~~~bash
Creating ECS cluster (ecs-demo-cluster) ... ✔
Creating VPC (ecs-demo-vpc) ... ✔
Creating Subnet (ecs-demo-subnet) ... ✔
Creating Internet Gateway (ecs-demo) ... ✔
Creating Security Group (ecs-demo) ... ✔
Creating Key Pair (ecs-demo-key.pem) ... ✔
Creating IAM role (ecs-role) ... ✔
Creating Launch Configuration (ecs-launch-configuration) ... ✔
Creating Auto Scaling Group (ecs-demo-group) with 3 instances ... ✔
Waiting for instances to join the cluster (this may take a moment) ... ✔
Registering ECS Task Definition (ecs-demo-task) ... ✔
Creating ECS Service with 3 tasks (ecs-demo-service) ... ✔
Waiting for tasks to start running ... ✔
ECS cluster contains: 
  http://ec2-52-43-201-147.us-west-2.compute.amazonaws.com
  http://ec2-52-43-162-49.us-west-2.compute.amazonaws.com
  http://ec2-52-38-20-31.us-west-2.compute.amazonaws.com
ECS cluster launched ... ✔
~~~

## Result

`setup.sh`:

* Created an Amazon ECS cluster
* Spawned 3 EC2 instances that are now part of the ECS cluster
* Created an ECS task family that describes the HTTP Server and API containers


## Verify

Navigate to one of 3 instances (response is from HTTP Server container):

~~~bash
launchy http://ec2-52-43-201-147.us-west-2.compute.amazonaws.com
~~~