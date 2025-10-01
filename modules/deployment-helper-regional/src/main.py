import boto3
import cfnresponse
import json
import logging
import os
import shutil
import terraform

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

LAMBDA_FUNCTION_ARN = None

TERRAFORM_STATE_BUCKET = os.getenv("TERRAFORM_STATE_BUCKET")
TERRAFORM_VERSION = "1.11.4"


def boto3_client(service, role_arn=None):
    if role_arn is None:
        return boto3.client(service)
    else:
        LOGGER.info("Attempting to assume role: %s", role_arn)
        sts_client = boto3.client("sts")
        response = sts_client.assume_role(
            RoleArn=role_arn,
            RoleSessionName=LAMBDA_FUNCTION_ARN.split(":")[6][:64],
            DurationSeconds=900,
        )
        LOGGER.info("Assumed role successfully.")
        return boto3.client(
            service,
            aws_access_key_id=response["Credentials"]["AccessKeyId"],
            aws_secret_access_key=response["Credentials"]["SecretAccessKey"],
            aws_session_token=response["Credentials"]["SessionToken"],
        )


def AWS__IAM__ServiceLinkedRole(event, context):
    match event["RequestType"]:
        case "Create" | "Update":
            iam_client = boto3_client("iam", event["ResourceProperties"]["RoleArn"])
            service_name = event["ResourceProperties"]["AWSServiceName"]
            try:
                LOGGER.info(
                    f"Attempting to create service-linked role for {service_name}"
                )
                response = iam_client.create_service_linked_role(
                    AWSServiceName=service_name
                )
                LOGGER.info(f"Created service-linked role for {service_name}.")
                cfnresponse.send(
                    event,
                    context,
                    cfnresponse.SUCCESS,
                    {},
                    physicalResourceId=response["Role"]["Arn"],
                )
            except iam_client.exceptions.InvalidInputException as e:
                LOGGER.info(f"Service-linked role for {service_name} already exists.")
                cfnresponse.send(
                    event,
                    context,
                    cfnresponse.SUCCESS,
                    {},
                    physicalResourceId=(
                        event["PhysicalResourceId"]
                        if "PhysicalResourceId" in event
                        else "AlreadyExisted"
                    ),
                )
        case "Delete":
            # AWS Service Linked Role deletion is not supported.
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        case _:
            raise Exception(f"Unsupported event type: {event['RequestType']}")


def TerraformDeployment(event, context):
    # In the event of a rollback CloudFormation sends a Delete event with the PhysicalResourceId not set to the previous state file.
    if event["RequestType"] == "Delete" and not event["PhysicalResourceId"].startswith("s3://"):
        cfnresponse.send(
            event,
            context,
            cfnresponse.SUCCESS,
            {},
            physicalResourceId=event["PhysicalResourceId"]
        )
        return
    tf_dir = "/tmp/terraform"
    work_dir = os.path.join(tf_dir, "work")
    # Clear the work directory of any previous invocations
    shutil.rmtree(work_dir, ignore_errors=True)
    os.makedirs(work_dir, exist_ok=True)
    os.chdir(work_dir)
    LOGGER.info(f"CWD: {os.getcwd()}")
    # Install Terraform if not already installed
    tf_binary = terraform.install(TERRAFORM_VERSION, tf_dir)
    # Copy stack into work directory
    LOGGER.info(f'Copying Terraform stack into "{work_dir}".')
    tf_src = event["ResourceProperties"]["Code"].replace("./", "/var/task/")
    shutil.copy(tf_src, work_dir)
    # Write variables file
    variables_file = os.path.join(work_dir, "variables.tfvars.json")
    tf_vars = { k: json.dumps(v) if isinstance(v, (dict, list)) else v for k, v in event["ResourceProperties"]["TFVARS"].items() }
    LOGGER.info(f'Writing variables to "{variables_file}".')
    with open(variables_file, "w") as f:
        json.dump(tf_vars, f)
    # Write backend file
    backend_file = os.path.join(work_dir, "_backend.tf")
    with open(backend_file, "w") as f:
        f.write("terraform {\n  backend \"s3\" {}\n}\n")
    # Write provider file with role assumption
    provider_file = os.path.join(work_dir, "_provider.tf")
    role_arn = event["ResourceProperties"]["RoleArn"]
    with open(provider_file, "w") as f:
        f.write('provider "aws" {\n  assume_role {\n    role_arn = "%s"\n  }\n}\n' % role_arn)
    # Determine state S3 bucket region
    LOGGER.info(f'Getting location for state bucket.')
    state_bucket_region = boto3_client("s3").get_bucket_location(Bucket=TERRAFORM_STATE_BUCKET).get("LocationConstraint")
    state_bucket_region = state_bucket_region if state_bucket_region else "us-east-1"
    state_bucket_region = "eu-west-1" if state_bucket_region == "EU" else state_bucket_region
    # terraform init with backend config
    stack_id_parts = event["StackId"].split(":")
    account_id = stack_id_parts[4]
    region = stack_id_parts[3]
    stack_ref = stack_id_parts[5]
    terraform_state_key = "/".join(event.get("PhysicalResourceId").split("/")[3:]) if event.get("PhysicalResourceId") else f"stackset-deploy/{account_id}/{region}/{stack_ref}/{event['LogicalResourceId']}.tfstate"
    state_object_uri = f"s3://{TERRAFORM_STATE_BUCKET}/{terraform_state_key}"
    terraform.init(
        tf_binary=tf_binary,
        bucket=TERRAFORM_STATE_BUCKET,
        key=terraform_state_key,
        region=state_bucket_region
    )
    # terraform plan
    is_delete = event["RequestType"] == "Delete"
    plan_file = os.path.join(work_dir, "tfplan")
    terraform.plan(
        out_file=plan_file,
        tf_binary=tf_binary,
        var_file=variables_file,
        destroy=is_delete
    )
    # terraform apply using the plan file
    terraform.apply(
        tf_binary=tf_binary,
        plan_file=plan_file
    )
    shutil.rmtree(work_dir)
    cfnresponse.send(
        event,
        context,
        cfnresponse.SUCCESS,
        {},
        physicalResourceId=event.get("PhysicalResourceId") or state_object_uri,
    )


def handler(event, context):
    global LAMBDA_FUNCTION_ARN
    LOGGER.info(json.dumps(event))
    for r in event["Records"]:
        message_body = json.loads(r["Sns"]["Message"])
        LOGGER.info(json.dumps(message_body))
        try:
            LAMBDA_FUNCTION_ARN = context.invoked_function_arn
            match message_body["ResourceType"]:
                case "Custom::AWS__IAM__ServiceLinkedRole":
                    AWS__IAM__ServiceLinkedRole(message_body, context)
                case "Custom::TerraformDeployment":
                    TerraformDeployment(message_body, context)
                case _:
                    raise Exception(
                        f"Unsupported resource type: {message_body['ResourceType']}"
                    )
        except Exception as e:
            LOGGER.error(repr(e))
            cfnresponse.send(
                message_body, context, cfnresponse.FAILED, {}, reason=repr(e)
            )
