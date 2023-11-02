#!/usr/bin/env bash
. ~/.bash_profile

export TEXT2TEXT_MODEL_ID=anthropic.claude-instant-v1
export EMBEDDING_MODEL_ID=amazon.titan-embed-text-v1
export BEDROCK_SERVICE=bedrock-runtime
echo "export TEXT2TEXT_MODEL_ID=${TEXT2TEXT_MODEL_ID}" \
    | tee -a ~/.bash_profile
echo "export EMBEDDING_MODEL_ID=${EMBEDDING_MODEL_ID}" \
    | tee -a ~/.bash_profile
echo "export BEDROCK_SERVICE=${BEDROCK_SERVICE}" \
    | tee -a ~/.bash_profile

export KUBECTL_VERSION="1.27.1/2023-04-19"

if [ "x${KUBECTL_VERSION}" == "x" ]
then
  echo "################"
  echo "Please specify a version for kubectl"
  echo "################"
  exit
fi

export EKS_CLUSTER_NAME="multitenant-chatapp"

if [ "x${EKS_CLUSTER_NAME}" == "x" ]
then
  echo "################"
  echo "Please specify a name for the EKS Cluster"
  echo "################"
  exit
fi

echo "export EKS_CLUSTER_NAME=${EKS_CLUSTER_NAME}" | tee -a ~/.bash_profile

export ISTIO_VERSION="1.18.3"

if [ "x${ISTIO_VERSION}" == "x" ]
then
  echo "################"
  echo "Please specify a version for Istio"
  echo "################"
  exit
fi

echo "export ISTIO_VERSION=${ISTIO_VERSION}" \
    | tee -a ~/.bash_profile

echo "Installing helper tools"
sudo yum -q -y install jq bash-completion
sudo amazon-linux-extras install -q -y python3.8 2>/dev/null >/dev/null
python3.8 -m pip install -q -q --user botocore
python3.8 -m pip install -q -q --user boto3

echo "Uninstalling AWS CLI 1.x"
sudo pip uninstall awscli -y

echo "Installing AWS CLI 2.x"
curl --silent --no-progress-meter \
    "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o "awscliv2.zip"
unzip -qq awscliv2.zip
sudo ./aws/install --update
PATH=/usr/local/bin:$PATH
/usr/local/bin/aws --version
rm -rf aws awscliv2.zip

CLOUD9_EC2_ROLE="Cloud9AdminRole"

AWS=$(which aws)

echo "---------------------------"
${AWS} sts get-caller-identity --query Arn | \
  grep ${CLOUD9_EC2_ROLE} -q && echo "IAM role valid. You can continue setting up the EKS Cluster." || \
  echo "IAM role NOT valid. Do not proceed with creating the EKS Cluster or you won't be able to authenticate.
  Ensure you assigned the role to your EC2 instance as detailed in the README.md"
echo "---------------------------"

export AWS_REGION=$(curl --silent --no-progress-meter \
                    http://169.254.169.254/latest/dynamic/instance-identity/document \
                    | jq -r '.region')
export AWS_DEFAULT_REGION=$AWS_REGION

export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)

export RANDOM_STRING=$(cat /dev/urandom \
                | tr -dc '[:alpha:]' \
                | fold -w ${1:-20} | head -n 1 \
                | cut -c 1-8 \
                | tr '[:upper:]' '[:lower:]')

echo "export RANDOM_STRING=${RANDOM_STRING}" | tee -a ~/.bash_profile

echo "Installing kubectl"
sudo curl --silent --no-progress-meter --location -o /usr/local/bin/kubectl \
  https://s3.us-west-2.amazonaws.com/amazon-eks/${KUBECTL_VERSION}/bin/linux/amd64/kubectl

sudo chmod +x /usr/local/bin/kubectl

kubectl version --client=true

echo "Installing bash completion for kubectl"
kubectl completion bash >>  ~/.bash_completion
. /etc/profile.d/bash_completion.sh
. ~/.bash_completion

echo "Installing eksctl"
curl --silent --no-progress-meter \
    --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
    | tar xz -C /tmp

sudo mv -v /tmp/eksctl /usr/local/bin

echo "eksctl Version: $(eksctl version)"

echo "Installing bash completion for eksctl"
eksctl completion bash >> ~/.bash_completion
. /etc/profile.d/bash_completion.sh
. ~/.bash_completion

test -n "$AWS_REGION" && echo AWS_REGION is "$AWS_REGION" || echo AWS_REGION is not set
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
echo "export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}" | tee -a ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region

export YAML_PATH=yaml
echo "export YAML_PATH=yaml" | tee -a ~/.bash_profile
[ -d ${YAML_PATH} ] || mkdir ${YAML_PATH}

export ENVOY_CONFIG_BUCKET="envoy-config-${RANDOM_STRING}"
aws s3 mb s3://${ENVOY_CONFIG_BUCKET}

if [[ $? -eq 0 ]]
then
    echo "export ENVOY_CONFIG_BUCKET=${ENVOY_CONFIG_BUCKET}" \
        | tee -a ~/.bash_profile
fi

# Creating S3 Bucket Policy for Envoy Dynamic Configuration Files
echo "Creating S3 Bucket Policy for Envoy Dynamic Configuration Files"
envsubst < iam/s3-envoy-config-access-policy.json | \
xargs -0 -I {} aws iam create-policy \
              --policy-name s3-envoy-config-access-policy-${RANDOM_STRING} \
              --policy-document {}

# Creating DynamoDB and Bedrock access policy for chatbot app
TENANTS="tenanta tenantb"
for t in $TENANTS
do
  export TENANT=${t}
  
  echo "Creating Contextual Data S3 Bucket for ${t}"
  aws s3 mb s3://contextual-data-${t}-${RANDOM_STRING}
  
  if [ "${t}" == "tenanta" ]
  then
      aws s3 cp data/Amazon_SageMaker_FAQs.csv s3://contextual-data-${t}-${RANDOM_STRING}
  elif [ "${t}" == "tenantb" ]
  then
      aws s3 cp data/Amazon_EMR_FAQs.csv s3://contextual-data-${t}-${RANDOM_STRING}
  fi
  
  echo "S3 access policy for ${t}"
  envsubst < iam/s3-contextual-data-access-policy.json | \
  xargs -0 -I {} aws iam create-policy \
                --policy-name s3-contextual-data-access-policy-${t}-${RANDOM_STRING} \
                --policy-document {}

  echo "DynamoDB and Bedrock access policy for ${t} chatbot app"
  envsubst < iam/dynamodb-access-policy.json | \
  xargs -0 -I {} aws iam create-policy \
                --policy-name dynamodb-access-policy-${t}-${RANDOM_STRING} \
                --policy-document {}
done

# Ingest Data to FAISS Index
source ~/.bash_profile
pip3.8 install -q -q --user -r data_ingestion_to_vectordb/requirements.txt
python3.8 data_ingestion_to_vectordb/data_ingestion_to_vectordb.py

echo "Creating Chatbot ECR Repository"
export ECR_REPO_CHATBOT=$(aws ecr create-repository \
  --repository-name ${EKS_CLUSTER_NAME}-${RANDOM_STRING}-chatbot \
  --encryption-configuration encryptionType=KMS)
export REPO_URI_CHATBOT=$(echo ${ECR_REPO_CHATBOT}|jq -r '.repository.repositoryUri')
export REPO_CHATBOT=$(echo ${ECR_REPO_CHATBOT}|jq -r '.repository.repositoryName')

echo "Creating rag-api ECR Repository"
export ECR_REPO_RAGAPI=$(aws ecr create-repository \
  --repository-name ${EKS_CLUSTER_NAME}-${RANDOM_STRING}-rag-api \
  --encryption-configuration encryptionType=KMS)
export REPO_URI_RAGAPI=$(echo ${ECR_REPO_RAGAPI}|jq -r '.repository.repositoryUri')
export REPO_RAGAPI=$(echo ${ECR_REPO_RAGAPI}|jq -r '.repository.repositoryName')

echo "export ECR_REPO_CHATBOT=${REPO_CHATBOT}" | tee -a ~/.bash_profile
echo "export REPO_URI_CHATBOT=${REPO_URI_CHATBOT}" | tee -a ~/.bash_profile
echo "export ECR_REPO_RAGAPI=${REPO_RAGAPI}" | tee -a ~/.bash_profile
echo "export REPO_URI_RAGAPI=${REPO_URI_RAGAPI}" | tee -a ~/.bash_profile

echo "Building Chatbot and RAG-API Images"
sh image-build/build-chatbot-image.sh
docker rmi -f $(docker images -a -q) &> /dev/null
sh image-build/build-rag-api-image.sh
docker rmi -f $(docker images -a -q) &> /dev/null

echo "Installing helm"
curl --no-progress-meter \
    -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

helm version --template='Version: {{.Version}}'; echo

rm -vf ${HOME}/.aws/credentials

echo "Generating a new key"
ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa <<< y

export EC2_KEY_NAME=${EKS_CLUSTER_NAME}-${RANDOM_STRING}
aws ec2 import-key-pair --key-name ${EC2_KEY_NAME} --public-key-material fileb://~/.ssh/id_rsa.pub
echo "export EC2_KEY_NAME=${EC2_KEY_NAME}" | tee -a ~/.bash_profile

echo "Creating KMS Key and Alias"
export KMS_KEY_ALIAS=${EKS_CLUSTER_NAME}-${RANDOM_STRING}
aws kms create-alias --alias-name alias/${KMS_KEY_ALIAS} \
    --target-key-id $(aws kms create-key --query KeyMetadata.Arn --output text)
echo "export KMS_KEY_ALIAS=${KMS_KEY_ALIAS}" | tee -a ~/.bash_profile

export MASTER_ARN=$(aws kms describe-key --key-id alias/${KMS_KEY_ALIAS} \
    --query KeyMetadata.Arn --output text)
echo "export MASTER_ARN=${MASTER_ARN}" | tee -a ~/.bash_profile
