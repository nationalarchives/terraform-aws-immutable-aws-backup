# Terraform Overview

This Terraform configuration provides a standardized and automated approach for managing resource deployments and associated data protection policies across multiple environments within an organizational structure. It leverages modular design to ensure reusability and consistency.

## Deployment Process and Created Resources

The configuration follows a structured, dependency-aware approach to provision resources and establish inter-environment communication.

###  1. Enviornment Context setup 

* The configuration identifies the unique identifiers of the current execution environment (e.g., account ID, organizational ID). This foundational step establishes the operational context within the broader organizational structure, providing necessary parameters for subsequent deployments.


###  2. Centeralised Helper Mechanism Deployment

* This is the first major deployment phase where it establishes a centeral automation utility which is then deployed to the designated central enviornement. It is an orchestrator for cross environment operations

* It provisions the automation utility which and the supporting infrastructure, this includes the creation of: 
    * AWS Lambda Function (for automation tasks)
    * SNS topic (event communication/notification)
    * IAM roles and policies that have a specific permissions and ARN pattern to adhere to. These are necessary as they enable the helper mechanism to securely interact with resources and assume roles within other connected environments. 
 

###  3. Service Deployment and Data Protection Configuration

* Once the centeralised helper machanism has been established the configuration will then proceed to deployment and setup of individual services. It provisions the necessary infrastructure specific to the service itself which are based on logic mentioned in the embedded modules, importantly it configures the required data protection methods for these resources. 

* Here the it would creates services focused on:

    * AWS Backup plans, defining when and how data should be backed up
    * AWS Backup vaults, where the actual backups are stored 
    * Retention policies, governing how long backups are kept  


###  4. Interfacing with other accounts

* The module has the ability to conduct backups in different accounts because its integrated with the previously deployed Centralised Automation Utility. It utlises the module called "deployment_helper_lambda" to facilitate cross-account operations, this is due to the fact it resides in the central account with the correct permissions to carry out specific tasks.

* The "deployment_helper_lambda" module is unique as it provides a delete option which terraform can do but cloudformation lacks in this functionality.

* I am roles play a curcial part here as they setup the ability to move across accounts more efficiently
* It is crucail to understand the use of some of the modules used here to make the ability to move across accounts 
feasible, this done with help of "service-deployment"

* Here it has one file called cloudformation.tf which is used to allow cross account work to be conducted. It has the capability of using stacks to allow the creation of member accounts with ease which terraform is too rigid for. 


![Architecture Diagram](assets/images/architecture.png?raw=true)