#!/usr/bin/bash
. ~/.bash_profile

echo "Installing Istio with Ingress Gateway (NLB)"
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
 
kubectl create namespace istio-system
kubectl create namespace istio-ingress

helm install istio-base istio/base \
    --namespace istio-system \
    --version ${ISTIO_VERSION} \
    --wait

helm install istiod istio/istiod \
  --namespace istio-system \
  --version ${ISTIO_VERSION} \
  --wait

helm list --namespace istio-system --filter 'istio+'

echo "Creating Istio Ingress Gateway, associating an internet-facing NLB instance"
echo "with Proxy v2 protocol and cross-AZ loadbalancing enabled"
LB_NAME=${EKS_CLUSTER_NAME}-nlb

helm install istio-ingressgateway istio/gateway \
  --namespace istio-ingress \
  --set "service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-type"='external' \
  --set "service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing" \
  --set "service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"='ip' \
  --set "service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-proxy-protocol"='*' \
  --set "service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-name"="${LB_NAME}" \
  --set "service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-attributes"='load_balancing.cross_zone.enabled=true' \
  --version ${ISTIO_VERSION} \
  --wait

helm ls -n istio-ingress

kubectl -n istio-system get svc
kubectl -n istio-system get pods
kubectl -n istio-ingress get svc
kubectl -n istio-ingress get pods

STATUS=$(aws elbv2 describe-load-balancers --name ${LB_NAME} \
  --query 'LoadBalancers[0].State.Code')

echo "Status of Load Balancer ${LB_NAME}: $STATUS"

# Enable Proxy v2 protocol processing on Istio Ingress Gateway
echo "Enabling Proxy v2 protocol processing on Istio Ingress Gateway"
kubectl -n istio-ingress apply -f istio-proxy-v2-config/proxy-protocol-envoy-filter.yaml
kubectl -n istio-ingress apply -f istio-proxy-v2-config/enable-X-Forwarded-For-header.yaml