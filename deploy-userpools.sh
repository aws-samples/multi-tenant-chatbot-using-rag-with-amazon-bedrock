#!/usr/bin/bash
. ~/.bash_profile

TENANTS="tenanta tenantb"
USERS="user1"

HOSTS=""

for t in $TENANTS
do
  echo "Creating User Pool for $t"
  export TENANT_ID=${t}
  POOLNAME=${t}_chatbot_example_com_${RANDOM_STRING}
  DOMAIN=${t}-chatbot-example-com-${RANDOM_STRING}
  CLIENTNAME=${t}_chatbot_client_${RANDOM_STRING}
  CALLBACKURL="https://${t}.example.com/oauth2/callback"
  LOGOUTURL="https://${t}.example.com"
  CUSTOM_ATTR=Name="tenantid",AttributeDataType="String",DeveloperOnlyAttribute=false,Mutable=true,Required=false,StringAttributeConstraints="{MinLength=1,MaxLength=20}"
  READ_ATTR="custom:tenantid"
  USER_ATTR=Name="custom:tenantid"

  export POOLINFO=$(aws cognito-idp create-user-pool \
  --pool-name ${POOLNAME} \
  --schema Name=email,AttributeDataType=String,DeveloperOnlyAttribute=false,Mutable=true,Required=true,StringAttributeConstraints="{MinLength=\"1\",MaxLength=\"64\"}" \
  --mfa-configuration OFF \
  --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false,TemporaryPasswordValidityDays=7}' \
  --username-configuration CaseSensitive=false \
  --admin-create-user-config AllowAdminCreateUserOnly=true)

  POOLID=$(echo $POOLINFO|jq -r '.UserPool.Id')

  echo "Adding Custom Attributes to User Pool"
  aws cognito-idp add-custom-attributes --user-pool-id ${POOLID} \
      --custom-attributes  ${CUSTOM_ATTR}

  echo "Creating User Pool Client for ${t}"
  CLIENT=$(aws cognito-idp create-user-pool-client \
  --user-pool-id ${POOLID} \
  --client-name ${CLIENTNAME} \
  --generate-secret \
  --refresh-token-validity "1" \
  --access-token-validity "1" \
  --id-token-validity "1" \
  --token-validity-units AccessToken="hours",IdToken="hours",RefreshToken="hours" \
  --read-attributes ${READ_ATTR})

  CLIENTID=$(echo $CLIENT|jq -r '.UserPoolClient.ClientId')
  CLIENTSECRET=$(echo $CLIENT|jq -r '.UserPoolClient.ClientSecret')

  echo "Setting User Pool Client Properties for ${t}"
  aws cognito-idp update-user-pool-client \
  --user-pool-id ${POOLID} \
  --client-id ${CLIENTID} \
  --explicit-auth-flows ALLOW_REFRESH_TOKEN_AUTH \
  --prevent-user-existence-errors "ENABLED" \
  --supported-identity-providers "COGNITO" \
  --callback-urls ${CALLBACKURL} \
  --logout-urls  ${LOGOUTURL} \
  --allowed-o-auth-flows "code" \
  --allowed-o-auth-scopes "openid" \
  --allowed-o-auth-flows-user-pool-client \
  --read-attributes "${READ_ATTR}" "email" "email_verified" 2>&1 > /dev/null

  echo "Creating User Pool Domain for ${t}"
  aws cognito-idp create-user-pool-domain \
  --domain ${DOMAIN} \
  --user-pool-id ${POOLID}

  for u in ${USERS}
  do
        USER=${u}@${t}.com
        echo "Creating ${USER} in ${POOLNAME}"
        read -s -p "Enter a Password for ${USER}: " PASSWORD
        printf "\n"
      
        aws cognito-idp admin-create-user \
        --user-pool-id ${POOLID} \
        --username ${USER}  2>&1 > /dev/null
        aws cognito-idp admin-set-user-password \
        --user-pool-id ${POOLID} \
        --username ${USER} \
        --password ${PASSWORD} \
        --permanent
      
        echo "Setting User Custom Attributes for ${USER}"
        aws cognito-idp admin-update-user-attributes \
            --user-pool-id ${POOLID} \
            --username ${USER} \
            --user-attributes ${USER_ATTR},Value="${TENANT_ID}"

        aws cognito-idp admin-update-user-attributes \
            --user-pool-id ${POOLID} \
            --username ${USER}	 \
            --user-attributes Name="email",Value="${USER}"
        
        aws cognito-idp admin-update-user-attributes \
            --user-pool-id ${POOLID} \
            --username ${USER}	 \
            --user-attributes Name="email_verified",Value="true"
  done

  HOST="${t}.example.com"
  CALLBACK_URI="https://${t}.example.com/oauth2/callback"
  export ISSUER_URI=https://cognito-idp.${AWS_REGION}.amazonaws.com/$POOLID
  COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32 | base64)

  echo "Creating AuthN Policy for ${t}"
  cat << EOF > ${YAML_PATH}/frontend-jwt-auth-${t}.yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: frontend-jwt-auth
spec:
  selector:
    matchLabels:
      workload-tier: frontend
  jwtRules:
  - issuer: "${ISSUER_URI}"
    forwardOriginalToken: true
    outputClaimToHeaders:
    - header: "x-auth-request-tenantid"
      claim: "custom:tenantid"

EOF

  echo "Creating AuthZ Policy for ${t}"
  cat << EOF > ${YAML_PATH}/frontend-authz-pol-${t}.yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: frontend-authz-pol
spec:
  selector:
    matchLabels:
      workload-tier: frontend
  action: ALLOW
  rules:
  - from:
    - source:
       namespaces: ["istio-ingress"]
       principals: ["cluster.local/ns/istio-ingress/sa/istio-ingressgateway"]
    when:
    - key: request.auth.claims[custom:tenantid]
      values: ["${TENANT_ID}"]
EOF

  echo "Creating oauth2-proxy Configuration for ${t}"
  cat << EOF > ${YAML_PATH}/oauth2-proxy-${t}-values.yaml
config:
  clientID: "${CLIENTID}"
  clientSecret: "${CLIENTSECRET}"
  cookieSecret: "${COOKIE_SECRET}="
  configFile: |-
    auth_logging = true
    cookie_httponly = true
    cookie_refresh = "1h"
    cookie_secure = true
    oidc_issuer_url = "${ISSUER_URI}"
    redirect_url = "${CALLBACK_URI}"
    scope="openid"
    reverse_proxy = true
    pass_host_header = true
    pass_access_token = true
    pass_authorization_header = true
    provider = "oidc"
    request_logging = true
    set_authorization_header = true
    set_xauthrequest = true
    session_store_type = "cookie"
    silence_ping_logging = true
    skip_provider_button = true
    skip_auth_strip_headers = false
    ssl_insecure_skip_verify = true
    skip_jwt_bearer_tokens = true
    standard_logging = true
    upstreams = [ "static://200" ]
    email_domains = [ "*" ]
    whitelist_domains = ["${t}.example.com"]
EOF

  NL=$'\n'
  HOSTS+="            - $HOST$NL"
  
  echo ""
done

echo "Creating AuthorizationPolicy on Istio Ingress Gateway"
cat << EOF > ${YAML_PATH}/chatbot-auth-policy.yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: cluster1-auth-policy
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingressgateway
  action: CUSTOM
  provider:
    name: rev-proxy
  rules:
    - to:
        - operation:
            hosts:
$HOSTS
EOF