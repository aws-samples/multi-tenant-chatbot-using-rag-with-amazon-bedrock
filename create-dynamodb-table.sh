#!/usr/bin/env bash
source ~/.bash_profile

TENANTS="tenanta tenantb"

for t in $TENANTS
do

    export TABLE_NAME="Sessions_${t}_${RANDOM_STRING}"
    
    echo "Creating DynamoDB table ${TABLE_NAME}"
    export DDB_TABLE=$(aws dynamodb create-table \
                        --table-name ${TABLE_NAME} \
                        --attribute-definitions \
                            AttributeName=TenantId,AttributeType=S \
                        --provisioned-throughput \
                            ReadCapacityUnits=5,WriteCapacityUnits=5 \
                        --key-schema \
                            AttributeName=TenantId,KeyType=HASH \
                        --table-class STANDARD
                        )
    
    export TABLE_NAME="ChatHistory_${t}_${RANDOM_STRING}"

    echo "Creating DynamoDB table ${TABLE_NAME}"
    export DDB_TABLE=$(aws dynamodb create-table \
                        --table-name ${TABLE_NAME} \
                        --attribute-definitions \
                            AttributeName=SessionId,AttributeType=S \
                        --provisioned-throughput \
                            ReadCapacityUnits=5,WriteCapacityUnits=5 \
                        --key-schema \
                            AttributeName=SessionId,KeyType=HASH \
                        --table-class STANDARD
                        )
done