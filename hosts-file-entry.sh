#!/usr/bin/bash
. ~/.bash_profile

export LB_FQDN=$(kubectl -n istio-ingress \
         get svc istio-ingressgateway \
         -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')

export LB_NAME=${EKS_CLUSTER_NAME}-nlb

STATUS=$(aws elbv2 describe-load-balancers --name ${LB_NAME} \
  --query 'LoadBalancers[0].State.Code' \
  | xargs)

echo "Status of Load Balancer ${LB_NAME}: $STATUS"

if [[ $STATUS == "active" ]]
then
    echo "You can update your hosts file with the following entries:"
    echo "---------------------------------------------------------"

    dig +noall +short +answer ${LB_FQDN} \
        | awk '{printf "%s\ttenanta.example.com\n%s\ttenantb.example.com\n",$0,$0}'
else
    echo 'Load Balancer is not ready!!! Try again, shortly.'
fi
