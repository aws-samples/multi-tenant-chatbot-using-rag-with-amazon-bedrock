# How to Build a Multitenant Chatbot with Retrieval Augmented Generation (RAG) using Amazon Bedrock and Amazon EKS

## BEFORE YOU START
In order to build this environment, ensure that your have access to the required Bedrock models
* Anthropic Claude Instant (Model Id: anthropic.claude-instant-v1)
* Titan Embeddings G1 - Text (Model Id: amazon.titan-embed-text-v1)

You can edit the **setup.sh** file to set the appropriate environment variables:
* TEXT2TEXT_MODEL_ID
* EMBEDDING_MODEL_ID

## CRITICAL STEPS
Pay close attention to **Steps 2 & 3**, otherwise the deployment will not succeed.

## Setting up the environment

> :warning: The Cloud9 workspace should be built by an IAM user with Administrator privileges, not the root account user. Please ensure you are logged in as an IAM user, not the root account user.

1. Create new Cloud9 Environment
    * Launch Cloud9 in your closest region Ex: `https://us-west-2.console.aws.amazon.com/cloud9/home?region=us-west-2`
    * Select Create environment
    * Name it whatever you want
    * Choose "t3.small" for instance type, take all default values and click Create environment
    * For Platform use "Amazon Linux 2"
2. Create EC2 Instance Role
    * Follow this [deep link](https://console.aws.amazon.com/iam/home#/roles$new?step=review&commonUseCase=EC2%2BEC2&selectedUseCase=EC2&policies=arn:aws:iam::aws:policy%2FAdministratorAccess) to create an IAM role with Administrator access.
    * Confirm that AWS service and EC2 are selected, then click `Next: Permissions` to view permissions.
    * Confirm that AdministratorAccess is checked, then click `Next: Tags` to assign tags.
    * Take the defaults, and click `Next: Review` to review.
    * Enter `Cloud9AdminRole` for the Name, and click `Create role`.
3. Remove managed credentials and attach EC2 Instance Role to Cloud9 Instance
    * Click the gear in the upper right-hand corner of the IDE which opens settings. Click the `AWS Settings` on the left and under `Credentials` slide the button to the left for `AWS Managed Temporary Credentials`. The button should be greyed out when done indicating it's off.
    * Click the round Button with an alphabet in the upper right-hand corner of the IDE and click `Manage EC2 Instance`. This will take you to the EC2 portion of the AWS Console
    * Right-click the Cloud9 EC2 instance and in the menu, click `Security` -> `Modify IAM Role`
    * Choose the Role you created in step 3 above. It should be titled `Cloud9AdminRole` and click `Save`.

4. Clone the repo and run the setup script
    * Return to the Cloud9 IDE
    * In the upper left part of the main screen, click the round green button with a `+` on it and click `New Terminal`
    * Enter the following in the terminal window

    ```bash
    git clone https://github.com/aws-samples/multi-tenant-chatbot-using-rag-with-amazon-bedrock.git
    cd multi-tenant-chatbot-using-rag-with-amazon-bedrock
    chmod +x setup.sh
    ./setup.sh
   ```

    This [script](./setup.sh) sets up all Kubernetes tools, updates the AWS CLI and installs other dependencies that we'll use later. Ensure that the Administrator EC2 role was created and successfully attached to the EC2 instance that's running your Cloud9 IDE. Also ensure you turned off `AWS Managed Credentials` inside your Cloud9 IDE (refer to steps 2 and 3).


5. Create and Populate DynamoDB Table
    > :warning: Close the terminal window that you created the cluster in, and open a new terminal before starting this step otherwise you may get errors about your AWS_REGION not set.
    * Open a **_NEW_** terminal window and `cd` back into `multi-tenant-chatbot-using-rag-with-amazon-bedrock` and run the following script:

    ```bash
    chmod +x create-dynamodb-table.sh
    ./create-dynamodb-table.sh
    ```

    This [script](./create-dynamodb-table.sh) creates the Session and ChatHistory DynamoDB tables for the chat application to maintain session information and LangChain chat history.

6. Create the EKS Cluster
    * Run the following script to create a cluster configuration file, and subsequently provision the cluster using `eksctl`:

    ```bash
    chmod +x deploy-eks.sh
    ./deploy-eks.sh
    ```

    This [script](./deploy-eks.sh) create a cluster configuration file, and subsequently provision the cluster using `eksctl`.
    
    The cluster will take approximately 30 minutes to deploy.

    After EKS Cluster is set up, the script also
    
    a. associate an OIDC provider with the Cluster
    
    b. deploys AWS Load Balancer Controller on the cluster
    
    c. creates IAM roles and policies for various containers to access S3, DynamoDB and Bedrock
    

7. Deploy Istio Service Mesh
    > :warning: Close the terminal window that you created the cluster in, and open a new terminal before starting this step otherwise you may get errors about your AWS_REGION not set.
    * Open a **_NEW_** terminal window and `cd` back into `multi-tenant-chatbot-using-rag-with-amazon-bedrock` and run the following script:

    ```bash
    chmod +x deploy-istio.sh
    ./deploy-istio.sh
    ```

    This [script](./deploy-istio.sh) deploys the Istio Service Mesh, including the Istio Ingress Gateway with Kubernetes annotations that signal the AWS Load Balancer Controller to automatically deploy a Network Load Balancer (NLB) and associate it with the Ingress Gateway service. It also enables proxy v2 protocol on the Istio Ingress Gateway that helps preserve the client IP forwarded by the NLB.


8. Deploy Cognito User Pools
    > :warning: Close the terminal window that you create the cluster in, and open a new terminal before starting this step otherwise you may get errors about your AWS_REGION not set.
    * Open a **_NEW_** terminal window and `cd` back into `multi-tenant-chatbot-using-rag-with-amazon-bedrock` and run the following script:

    ```bash
    chmod +x deploy-userpools.sh
    ./deploy-userpools.sh
    ```

    This [script](./deploy-userpools.sh) deploys Cognito User Pools for two (2) example tenants: tenanta and tenantb. Within each User Pool. The script will ask for passwords that will be set for each user.

    The script also generates the YAML files for OIDC proxy configuration which will be deployed in the next step: 

    a. oauth2-proxy configuration for each tenant

    b. External Authorization Policy for Istio Ingress Gateway
    

9. Configure Istio Ingress Gateway
    > :warning: Close the terminal window that you create the cluster in, and open a new terminal before starting this step otherwise you may get errors about your AWS_REGION not set.
    * Open a **_NEW_** terminal window and `cd` back into `multi-tenant-chatbot-using-rag-with-amazon-bedrock` and run the following script:

    ```bash
    chmod +x configure-istio.sh
    ./configure-istio.sh
    ```

    This [script](./configure-istio.sh) creates the following to configure the Istio Ingress Gateway:

    a. Self-signed Root CA Cert and Key

    b. Istio Ingress Gateway Cert signed by the Root CA

    It also completes the following steps:

    a. Creates TLS secret object for Istio Ingress Gateway Cert and Key

    b. Creates namespaces for Gateway, Envoy Reverse Proxy, OIDC Proxies, and the example tenants

    c. Deploys an Istio Gateway resource

    d. Deploys an Envoy reverse proxy

    e. Deploy oauth2-proxy along with the configuration generated in the Step 8

    f. Adds an Istio External Authorization Provider definition pointing to the Envoy Reverse Proxy


10. Deploy Tenant Application Microservices
    > :warning: Close the terminal window that you create the cluster in, and open a new terminal before starting this step otherwise you may get errors about your AWS_REGION not set.
    * Open a **_NEW_** terminal window and `cd` back into `multi-tenant-chatbot-using-rag-with-amazon-bedrock` and run the following script:

    ```bash
    chmod +x deploy-tenant-services.sh
    ./deploy-tenant-services.sh
    ```

    This [script](./deploy-tenant-services.sh) creates the service dpeloyments for the two (2) sample tenants, along with Istio VirtualService constructs that define the routing rules.


11. Once finished running all the above steps, the bookinfo app can be accessed using the following steps.

    a. Run the following command in the Cloud9 shell
    ```bash
    chmod +x hosts-file-entry.sh
    ./hosts-file-entry.sh
    ```

    b. Append the output of the command into your local hosts file. It identifies the load balancer instance associated with the Istio Ingress Gateway, and looks up the public IP addresses assigned to it.

    c. To avoid TLS cert conflicts, configure the browser on desktop/laptop with a new profiles

    d. The browser used to test this deployment was Mozilla Firefox, in which a new profile can be created by pointing the browser to "about:profiles"

    e. Create a new profile, such as, "multitenant-chatbot"

    f. After creating the profile, click on the "Launch profile in new browser"

    g. In the browser, open two tabs, one for each of the following URLs:

    ```
       https://tenanta.example.com/

       https://tenantb.example.com/
    ```

    h. Because of self-signed TLS certificates, you may received a certificate related error or warning from the browser

    i. When the login prompt appears:

       In the browser windows with the "multitenant-chatapp" profile, login with:

    ```
       user1@tenanta.com

       user1@tenantb.com
    ```

## Sample Prompts

# Tenant A
* What are Foundation Models
* Can I use R in SageMaker
* how to detect statistical bias across a model training workflow
* how can i monitor the performance of a model and take corrective action when drift is detected
* what is tranium
* what is inferentia

# Tenant B
* What are the applications of Impala
* How to use HBase in EMR
* What does it mean when the EMR cluster is BOOTSTRAPPING
* How to use Kinesis for data ingestion

## Cleanup

1. The deployed components can be cleaned up by running the following:

    ```bash
    chmod +x cleanup.sh
    ./cleanup.sh
    ```

2. You can also delete

    a. The EC2 Instance Role `Cloud9AdminRole`

    b. The Cloud9 Environment

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

