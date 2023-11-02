#!/usr/bin/env bash
. ~/.bash_profile

aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS \
  --password-stdin ${REPO_URI_RAGAPI}

ECR_IMAGE=$(
    aws ecr list-images \
         --repository-name ${ECR_REPO_RAGAPI} \
         --query 'imageIds[0].imageDigest' \
         --output text
    )

aws ecr batch-delete-image \
     --repository-name ${ECR_REPO_RAGAPI} \
     --image-ids imageDigest=${ECR_IMAGE}

docker build -f image-build/Dockerfile-api -t ${REPO_URI_RAGAPI}:latest .
docker push ${REPO_URI_RAGAPI}:latest