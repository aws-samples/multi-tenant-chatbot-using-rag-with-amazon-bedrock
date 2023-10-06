#!/usr/bin/bash
. ~/.bash_profile

# Add oauth2-proxy Helm Repo
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests

TENANTS="tenanta tenantb"

for t in $TENANTS
do
    export TENANT="${t}"
    export SA_NAME="${t}-sa"
    export NAMESPACE="${t}-ns"
    export DOMAIN="${t}-chatbot-example-com-${RANDOM_STRING}"

    USERPOOL_ID=$(
      aws cognito-idp describe-user-pool-domain \
      --domain ${DOMAIN} \
      --query 'DomainDescription.UserPoolId' \
      --output text | xargs
      )
    export ISSUER_URI=https://cognito-idp.${AWS_REGION}.amazonaws.com/${USERPOOL_ID}
    export SESSIONS_TABLE=Sessions_${t}_${RANDOM_STRING}
    export CHATHISTORY_TABLE=ChatHistory_${t}_${RANDOM_STRING}
    
    echo "Deploying ${t} services ..."

    echo "-> Deploying chatbot service"
    
    envsubst < chatbot-manifest/chatbot.yaml | kubectl -n ${NAMESPACE} apply -f -

    echo "Applying Frontend Authentication Policy for ${t}"
    kubectl -n ${NAMESPACE} apply -f ${YAML_PATH}/frontend-jwt-auth-${t}.yaml
    rm -rf ${YAML_PATH}/frontend-jwt-auth-${t}.yaml

    echo "Applying Frontend Authorization Policy for ${t}"
    kubectl -n ${NAMESPACE} apply -f ${YAML_PATH}/frontend-authz-pol-${t}.yaml
    rm -rf ${YAML_PATH}/frontend-authz-pol-${t}.yaml
   
    echo "-> Deploying VirtualService to expose chatbot via Ingress Gateway"
    envsubst < chatbot-manifest/chatbot-vs.yaml | kubectl -n ${NAMESPACE} apply -f -
    echo "Deploying OIDC Proxy for ${t}"
    helm install --namespace ${t}-oidc-proxy-ns oauth2-proxy \
      oauth2-proxy/oauth2-proxy -f ${YAML_PATH}/oauth2-proxy-${t}-values.yaml
    rm -rf ${YAML_PATH}/oauth2-proxy-${t}-values.yaml
done