#!/usr/bin/bash
source ~/.bash_profile

test -n "$EKS_CLUSTER_NAME" && echo EKS_CLUSTER_NAME is "$EKS_CLUSTER_NAME" || echo EKS_CLUSTER_NAME is not set

export EKS_CLUSTER_VERSION="1.27"
echo "Deploying Cluster ${EKS_CLUSTER_NAME} with EKS ${EKS_CLUSTER_VERSION}"

cat << EOF > ${YAML_PATH}/cluster-config.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${EKS_CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "${EKS_CLUSTER_VERSION}"
iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: aws-load-balancer-controller
      namespace: kube-system
    wellKnownPolicies:
      awsLoadBalancerController: true
availabilityZones: ["${AWS_REGION}a", "${AWS_REGION}b", "${AWS_REGION}c"]
managedNodeGroups:
- name: nodegroup
  desiredCapacity: 3
  instanceTypes: ["t3a.medium", "t3.medium"]
  volumeEncrypted: true
  ssh:
    allow: false
cloudWatch:
  clusterLogging:
    enableTypes: ["*"]
secretsEncryption:
  keyARN: ${MASTER_ARN}
EOF

eksctl create cluster -f ${YAML_PATH}/cluster-config.yaml

aws eks update-kubeconfig --name=${EKS_CLUSTER_NAME}

# Associate an OIDC provider with the EKS Cluster
echo "Associating an OIDC provider with the EKS Cluster"
eksctl utils associate-iam-oidc-provider \
--region=${AWS_REGION} \
--cluster=${EKS_CLUSTER_NAME} \
--approve

export OIDC_PROVIDER=$(aws eks describe-cluster \
                      --name ${EKS_CLUSTER_NAME} \
                      --query "cluster.identity.oidc.issuer" \
                      --output text)

echo "Installing AWS Load Balancer Controller"

kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

helm repo add eks https://aws.github.io/eks-charts

helm repo update

# Setting AWS Load Balancer Controller Version
export VPC_ID=$(aws eks describe-cluster \
                --name ${EKS_CLUSTER_NAME} \
                --query "cluster.resourcesVpcConfig.vpcId" \
                --output text)

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=${EKS_CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set region=${AWS_REGION} \
  --set vpcId=${VPC_ID} \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl -n kube-system rollout status deployment aws-load-balancer-controller

export OIDC_PROVIDER=$(aws eks describe-cluster \
                      --name ${EKS_CLUSTER_NAME} \
                      --query "cluster.identity.oidc.issuer" \
                      --output text)

export OIDC_ID=$(echo $OIDC_PROVIDER | awk -F/ '{print $NF}')

echo "Creating S3 Access Role in IAM"
export S3_ACCESS_ROLE=${EKS_CLUSTER_NAME}-s3-access-role-${RANDOM_STRING}
export ENVOY_IRSA=$(
envsubst < iam/s3-access-role-trust-policy.json | \
xargs -0 -I {} aws iam create-role \
              --role-name ${S3_ACCESS_ROLE} \
              --assume-role-policy-document {} \
              --query 'Role.Arn' \
              --output text
)
echo "Attaching S3 Bucket policy to S3 Access Role"
aws iam attach-role-policy \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/s3-envoy-config-access-policy-${RANDOM_STRING} \
    --role-name ${S3_ACCESS_ROLE}

echo ${ENVOY_IRSA}
echo "export ENVOY_IRSA=${ENVOY_IRSA}" \
    | tee -a ~/.bash_profile

TENANTS="tenanta tenantb"
for t in $TENANTS
do
  export NAMESPACE="${t}-ns"
  export SA_NAME="${t}-sa"

  echo "Creating DynamoDB / Bedrock Access Role in IAM"
  export CHATBOT_ACCESS_ROLE=${EKS_CLUSTER_NAME}-${t}-chatbot-access-role-${RANDOM_STRING}
  export CHATBOT_IRSA=$(
  envsubst < iam/chatbot-access-role-trust-policy.json | \
  xargs -0 -I {} aws iam create-role \
                --role-name ${CHATBOT_ACCESS_ROLE} \
                --assume-role-policy-document {} \
                --query 'Role.Arn' \
                --output text
  )
  echo "Attaching S3 Bucket and DynamoDB policy to Chatbot Access Role"
  aws iam attach-role-policy \
      --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/s3-contextual-data-access-policy-${t}-${RANDOM_STRING} \
      --role-name ${CHATBOT_ACCESS_ROLE}
      
  aws iam attach-role-policy \
      --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/dynamodb-access-policy-${t}-${RANDOM_STRING} \
      --role-name ${CHATBOT_ACCESS_ROLE}
done