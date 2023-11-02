#!/usr/bin/bash
. ~/.bash_profile

# Directory for generated certs
mkdir certs

echo "Creating Root CA Cert and Key"
openssl req -x509 -sha256 -nodes -days 365 \
  -newkey rsa:2048 \
  -subj '/O=Cluster 1 CA/CN=ca.example.com' \
  -keyout certs/ca_example_com.key \
  -out certs/ca_example_com.crt

echo "Creating Cert and Key for Istio Ingress Gateway"
openssl req \
  -newkey rsa:2048 -nodes \
  -subj "/O=Cluster 1/CN=*.example.com" \
  -keyout certs/example_com.key \
  -out certs/example_com.csr

openssl x509 -req -days 365 \
  -set_serial 0 \
  -CA certs/ca_example_com.crt \
  -CAkey certs/ca_example_com.key \
  -in certs/example_com.csr \
  -out certs/example_com.crt

echo "Creating TLS secret for Istio Ingress Gateway"
kubectl create -n istio-ingress secret generic credentials \
  --from-file=tls.key=certs/example_com.key \
  --from-file=tls.crt=certs/example_com.crt

echo "Creating namespaces"
kubectl create namespace llm-demo-gateway-ns
kubectl create namespace envoy-reverse-proxy-ns
kubectl create namespace tenanta-oidc-proxy-ns
kubectl create namespace tenantb-oidc-proxy-ns
kubectl create namespace tenanta-ns
kubectl create namespace tenantb-ns

echo "Enabling sidecar injection in namespaces"
kubectl label namespace envoy-reverse-proxy-ns istio-injection=enabled
kubectl label namespace tenanta-oidc-proxy-ns istio-injection=enabled
kubectl label namespace tenantb-oidc-proxy-ns istio-injection=enabled
kubectl label namespace tenanta-ns istio-injection=enabled
kubectl label namespace tenantb-ns istio-injection=enabled

kubectl get namespace -L istio-injection

echo "Applying STRICT mTLS Policy on all application namespaces"
cat << EOF > ${YAML_PATH}/strictmtls.yaml
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: strict-mtls
spec:
  mtls:
    mode: STRICT
EOF
kubectl -n tenanta-ns apply -f ${YAML_PATH}/strictmtls.yaml
kubectl -n tenantb-ns apply -f ${YAML_PATH}/strictmtls.yaml
kubectl -n envoy-reverse-proxy-ns apply -f ${YAML_PATH}/strictmtls.yaml

kubectl -n tenanta-ns get PeerAuthentication
kubectl -n tenantb-ns get PeerAuthentication
kubectl -n envoy-reverse-proxy-ns get PeerAuthentication

rm -rf ${YAML_PATH}/strictmtls.yaml

echo "Deploying Istio Gateway resource"
cat << EOF > ${YAML_PATH}/llm-demo-gateway.yaml
---
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: llm-demo-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: credentials
        minProtocolVersion: TLSV1_2
        maxProtocolVersion: TLSV1_3
      hosts:
        - 'tenanta-ns/*'
        - 'tenantb-ns/*'
EOF
kubectl -n llm-demo-gateway-ns apply -f ${YAML_PATH}/llm-demo-gateway.yaml

rm -rf ${YAML_PATH}/llm-demo-gateway.yaml

# Copying Envoy Dynamic Config files to S3 bucket
echo "Copying Envoy Dynamic Config files to S3 bucket"
aws s3 cp envoy-config/envoy.yaml s3://${ENVOY_CONFIG_BUCKET}
aws s3 cp envoy-config/envoy-lds.yaml s3://${ENVOY_CONFIG_BUCKET}
aws s3 cp envoy-config/envoy-cds.yaml s3://${ENVOY_CONFIG_BUCKET}

echo "Deploying Envoy Reverse Proxy"
export DOLLAR='$'
cat << EOF > ${YAML_PATH}/envoy-reverse-proxy.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${ACCOUNT_ID}:role/${EKS_CLUSTER_NAME}-s3-access-role-${RANDOM_STRING}
  name: envoy-reverse-proxy-sa
---
apiVersion: v1
kind: Service
metadata:
  name: envoy-reverse-proxy
  labels:
    app: envoy-reverse-proxy
spec:
  selector:
    app: envoy-reverse-proxy
  ports:
  - port: 80
    name: http
    targetPort: 8000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: envoy-reverse-proxy
  labels:
    app: envoy-reverse-proxy
spec:
  replicas: 2
  selector:
    matchLabels:
      app: envoy-reverse-proxy
  minReadySeconds: 60
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: envoy-reverse-proxy
      annotations:
        eks.amazonaws.com/skip-containers: "envoy-reverse-proxy"
    spec:
      serviceAccountName: envoy-reverse-proxy-sa
      initContainers:
      - name: envoy-reverse-proxy-bootstrap
        image: public.ecr.aws/aws-cli/aws-cli:2.13.6
        volumeMounts:
        - name: envoy-config-volume
          mountPath: /config/envoy
        command: ["/bin/sh", "-c"]
        args:
          - aws s3 cp s3://${DOLLAR}{ENVOY_CONFIG_S3_BUCKET}/envoy.yaml /config/envoy;
            aws s3 cp s3://${DOLLAR}{ENVOY_CONFIG_S3_BUCKET}/envoy-lds.yaml /config/envoy;
            aws s3 cp s3://${DOLLAR}{ENVOY_CONFIG_S3_BUCKET}/envoy-cds.yaml /config/envoy;
        env:
        - name: ENVOY_CONFIG_S3_BUCKET
          value: ${ENVOY_CONFIG_BUCKET}
      containers:
      - name: envoy-reverse-proxy
        image: envoyproxy/envoy:v1.27.0
        args: ["-c", "/config/envoy/envoy.yaml"]
        imagePullPolicy: Always
        ports:
          - containerPort: 8000
        volumeMounts:
        - name: envoy-config-volume
          mountPath: /config/envoy
      volumes:
      - name: envoy-config-volume
        emptyDir: {}
EOF
kubectl -n envoy-reverse-proxy-ns apply -f ${YAML_PATH}/envoy-reverse-proxy.yaml

rm -rf ${YAML_PATH}/envoy-reverse-proxy.yaml

echo "Adding Istio External Authorization Provider"
cat << EOF > ${YAML_PATH}/auth-provider.yaml
---
apiVersion: v1
data:
  mesh: |-
    accessLogFile: /dev/stdout
    defaultConfig:
      discoveryAddress: istiod.istio-system.svc:15012
      proxyMetadata: {}
      tracing:
        zipkin:
          address: zipkin.istio-system:9411
    enablePrometheusMerge: true
    rootNamespace: istio-system
    trustDomain: cluster.local
    extensionProviders:
    - name: rev-proxy
      envoyExtAuthzHttp:
        service: envoy-reverse-proxy.envoy-reverse-proxy-ns.svc.cluster.local
        port: "80"
        timeout: 1.5s
        includeHeadersInCheck: ["authorization", "cookie"]
        headersToUpstreamOnAllow: ["authorization", "path", "x-auth-request-user", "x-auth-request-email"]
        headersToDownstreamOnDeny: ["content-type", "set-cookie"]
EOF
kubectl -n istio-system patch configmap istio --patch "$(cat ${YAML_PATH}/auth-provider.yaml)"
kubectl rollout restart deployment/istiod -n istio-system

rm -rf ${YAML_PATH}/auth-provider.yaml

echo "Configuring AuthorizationPolicy on Istio Ingress Gateway"
kubectl apply -f ${YAML_PATH}/chatbot-auth-policy.yaml
rm -rf ${YAML_PATH}/chatbot-auth-policy.yaml