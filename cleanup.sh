#!/usr/bin/bash
source ~/.bash_profile

echo "Deleting CloudFormation Resources"
export EKS_NODEGROUP=eksctl-${EKS_CLUSTER_NAME}-nodegroup-nodegroup
export EKS_NODE=eksctl-${EKS_CLUSTER_NAME}-addon-iamserviceaccount-kube-system-aws-node
export EKS_NLB=eksctl-${EKS_CLUSTER_NAME}-addon-iamserviceaccount-kube-system-aws-load-balancer-controller   
export CF_CLUSTER=eksctl-${EKS_CLUSTER_NAME}-cluster

aws cloudformation delete-stack --stack-name ${EKS_NODEGROUP}
aws cloudformation delete-stack --stack-name ${EKS_NODE}    
aws cloudformation delete-stack --stack-name ${EKS_NLB}
aws cloudformation delete-stack --stack-name ${CF_CLUSTER}

echo "Deleting ECR Repositories"
aws ecr delete-repository \
  --force \
  --repository-name ${EKS_CLUSTER_NAME}-${RANDOM_STRING}-chatbot  2>&1 > /dev/null

aws ecr delete-repository \
  --force \
  --repository-name ${EKS_CLUSTER_NAME}-${RANDOM_STRING}-rag-api  2>&1 > /dev/null

docker_images=$(docker images -a -q)
if [ ! -z "$docker_images" ]
then
	docker rmi -f $(docker images -a -q)
fi

echo "Deleting Envoy Config S3 Bucket"
aws s3 rm s3://envoy-config-${RANDOM_STRING} --recursive
aws s3 rb s3://envoy-config-${RANDOM_STRING} --force

echo "Detaching IAM policies from Envoy & Chatbot SA Roles"
aws iam detach-role-policy \
    --role-name ${EKS_CLUSTER_NAME}-s3-access-role-${RANDOM_STRING} \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/s3-envoy-config-access-policy-${RANDOM_STRING}

echo "Deleting S3 Access SA Roles in IAM"
aws iam delete-role \
    --role-name ${EKS_CLUSTER_NAME}-s3-access-role-${RANDOM_STRING}

aws iam delete-policy \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/s3-envoy-config-access-policy-${RANDOM_STRING}

TENANTS="tenanta tenantb"
for t in $TENANTS
do
    POOLNAME=${t}_chatbot_example_com_${RANDOM_STRING}
    POOLID=$(aws cognito-idp list-user-pools \
            --max-results 20 \
            --query 'UserPools[?Name==`'${POOLNAME}'`].Id' \
            --output text)
    DOMAIN=$(aws cognito-idp describe-user-pool \
            --user-pool-id ${POOLID} \
            --query 'UserPool.Domain' \
            --output text)

    aws cognito-idp delete-user-pool-domain \
      --user-pool-id ${POOLID} \
      --domain ${DOMAIN}

    aws cognito-idp delete-user-pool \
      --user-pool-id ${POOLID}

    aws s3 rm s3://contextual-data-${t}-${RANDOM_STRING} --recursive
    aws s3 rb s3://contextual-data-${t}-${RANDOM_STRING} --force

    aws dynamodb delete-table \
        --table-name Sessions_${t}_${RANDOM_STRING}
    aws dynamodb delete-table \
        --table-name ChatHistory_${t}_${RANDOM_STRING}

    aws iam detach-role-policy \
        --role-name ${EKS_CLUSTER_NAME}-${t}-chatbot-access-role-${RANDOM_STRING} \
        --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/s3-contextual-data-access-policy-${t}-${RANDOM_STRING}
    
    aws iam detach-role-policy \
        --role-name ${EKS_CLUSTER_NAME}-${t}-chatbot-access-role-${RANDOM_STRING} \
        --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/dynamodb-access-policy-${t}-${RANDOM_STRING}

    aws iam delete-role \
        --role-name ${EKS_CLUSTER_NAME}-${t}-chatbot-access-role-${RANDOM_STRING}

    aws iam delete-policy \
        --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/s3-contextual-data-access-policy-${t}-${RANDOM_STRING}
    aws iam delete-policy \
        --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/dynamodb-access-policy-${t}-${RANDOM_STRING}
done

echo "Removing KMS Key and Alias"
export KMS_KEY_ALIAS=${EKS_CLUSTER_NAME}-${RANDOM_STRING}
export MASTER_ARN=$(aws kms describe-key \
  --key-id alias/${KMS_KEY_ALIAS} \
  --query KeyMetadata.Arn --output text)

aws kms disable-key \
  --key-id ${MASTER_ARN}

aws kms delete-alias \
  --alias-name alias/${KMS_KEY_ALIAS}

echo "Deleting EC2 Key-Pair"
aws ec2 delete-key-pair \
  --key-name ${EC2_KEY_NAME}

echo "Removing Environemnt Variables from .bash_profile"
sed -i '/export ACCOUNT_ID/d' ~/.bash_profile
sed -i '/export AWS_REGION/d' ~/.bash_profile
sed -i '/export AWS_DEFAULT_REGION/d' ~/.bash_profile
sed -i '/export YAML_PATH/d' ~/.bash_profile
sed -i '/export EKS_CLUSTER_NAME/d' ~/.bash_profile
sed -i '/export RANDOM_STRING/d' ~/.bash_profile
sed -i '/export EC2_KEY_NAME/d' ~/.bash_profile
sed -i '/export KMS_KEY_ALIAS/d' ~/.bash_profile
sed -i '/export MASTER_ARN/d' ~/.bash_profile
sed -i '/export ISTIO_VERSION/d' ~/.bash_profile
sed -i '/export ENVOY_CONFIG_BUCKET/d' ~/.bash_profile
sed -i '/export ECR_REPO_CHATBOT/d' ~/.bash_profile
sed -i '/export REPO_URI_CHATBOT/d' ~/.bash_profile
sed -i '/export ECR_REPO_RAGAPI/d' ~/.bash_profile
sed -i '/export REPO_URI_RAGAPI/d' ~/.bash_profile
sed -i '/export ENVOY_IRSA/d' ~/.bash_profile
sed -i '/export BEDROCK_REGION/d' ~/.bash_profile
sed -i '/export BEDROCK_ENDPOINT/d' ~/.bash_profile
sed -i '/export TEXT2TEXT_MODEL_ID/d' ~/.bash_profile
sed -i '/export EMBEDDING_MODEL_ID/d' ~/.bash_profile
sed -i '/export BEDROCK_SERVICE/d' ~/.bash_profile
sed -i '/export EKS_NODEGROUP/d' ~/.bash_profile
sed -i '/export EKS_NODE/d' ~/.bash_profile
sed -i '/export EKS_NLB/d' ~/.bash_profile
sed -i '/export CF_CLUSTER/d' ~/.bash_profile

unset ACCOUNT_ID
unset AWS_REGION
unset AWS_DEFAULT_REGION
unset YAML_PATH
unset EKS_CLUSTER_NAME
unset RANDOM_STRING
unset EC2_KEY_NAME
unset KMS_KEY_ALIAS
unset MASTER_ARN
unset ISTIO_VERSION
unset ENVOY_CONFIG_BUCKET
unset ECR_REPO_CHATBOT
unset REPO_URI_CHATBOT
unset ECR_REPO_RAGAPI
unset REPO_URI_RAGAPI
unset ENVOY_IRSA
unset BEDROCK_REGION
unset BEDROCK_ENDPOINT
unset TEXT2TEXT_MODEL_ID
unset EMBEDDING_MODEL_ID
unset BEDROCK_SERVICE

rm -rf $HOME/.ssh/id_rsa
rm -rf certs
rm -rf yaml
rm -rf faiss_index*
rm -rf bedrock-sdk/*