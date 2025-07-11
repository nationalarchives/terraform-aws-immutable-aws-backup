import boto3
import cfnresponse
import json
import logging
import os
import shutil
import subprocess
from urllib.request import urlretrieve
from zipfile import ZipFile

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
    iam_client = boto3_client("iam", event["ResourceProperties"]["RoleArn"])
    match event["RequestType"]:
        case "Create" | "Update":
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
    tf_dir = "/tmp/terraform"
    tf_binary = os.path.join(tf_dir, "terraform")
    work_dir = os.path.join(tf_dir, "work")
    shutil.rmtree(work_dir, ignore_errors=True)
    os.makedirs(work_dir, exist_ok=True)
    os.chdir(work_dir)
    LOGGER.info(f"CWD: {os.getcwd()}")
    # Install Terraform if not already installed
    if not os.path.exists(tf_binary):
        LOGGER.info(f'Installing Terraform to "{tf_binary}".')
        os.makedirs(tf_dir, exist_ok=True)
        terraform_url = f"https://releases.hashicorp.com/terraform/{TERRAFORM_VERSION}/terraform_{TERRAFORM_VERSION}_linux_amd64.zip"
        zip_path = os.path.join(tf_dir, "terraform.zip")
        LOGGER.info(f'Downloading Terraform from "{terraform_url}" to "{zip_path}".')
        urlretrieve(terraform_url, zip_path)
        LOGGER.info(f'Extracting Terraform from "{zip_path}" to "{tf_dir}".')
        with ZipFile(zip_path, "r") as zip_ref:
            zip_ref.extractall(tf_dir)
        os.chmod(tf_binary, 0o755)
        os.remove(zip_path)
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
    # Write provider file
    provider_file = os.path.join(work_dir, "provider.tf")
    role_arn = event["ResourceProperties"]["RoleArn"]
    with open(provider_file, "w") as f:
        f.write('provider "aws" {\n')
        f.write("  assume_role {\n")
        f.write(f'    role_arn = "{role_arn}"\n')
        f.write("  }\n")
        f.write("}\n")
    # Write backend file
    backend_file = os.path.join(work_dir, "_backend.tf")
    stack_id_parts = event["StackId"].split(":")
    account_id = stack_id_parts[4]
    region = stack_id_parts[3]
    stack_ref = stack_id_parts[5]
    terraform_state_key = "/".join(event.get("PhysicalResourceId").split("/")[3:]) if event.get("PhysicalResourceId") else f"stackset-deploy/{account_id}/{region}/{stack_ref}/{event['LogicalResourceId']}.tfstate"
    state_object_uri = f"s3://{TERRAFORM_STATE_BUCKET}/{terraform_state_key}"
    LOGGER.info(f'Using state file "{state_object_uri}".')
    with open(backend_file, "w") as f:
        f.write("terraform {\n")
        f.write('  backend "s3" {\n')
        f.write(f'    bucket = "{TERRAFORM_STATE_BUCKET}"\n')
        f.write(f'    key = "{terraform_state_key}"\n')
        f.write("  }\n")
        f.write("}\n")
    # terraform init
    LOGGER.info(f"Initialising Terraform.")
    try:
        init_result = subprocess.run(
            [tf_binary, "init", "-no-color"],
            capture_output=True,
            text=True,
            check=True,
        )
        LOGGER.info(init_result.stdout)
        LOGGER.info(init_result.stderr)
    except subprocess.CalledProcessError as e:
        LOGGER.error(f"Terraform init failed: {e.stderr}")
        raise Exception(f"Terraform init failed: {e.stderr}") from e
    # terraform apply --auto-approve
    LOGGER.info(f"Applying Terraform.")
    try:
        apply_result = subprocess.run(
            list(
                filter(
                    None,
                    [
                        tf_binary,
                        "apply",
                        "-no-color",
                        "-auto-approve",
                        f"-var-file={variables_file}",
                        *["-destroy" if event["RequestType"] == "Delete" else None],
                    ],
                )
            ),
            capture_output=True,
            text=True,
            check=True,
        )
        LOGGER.info(apply_result.stdout)
        LOGGER.info(apply_result.stderr)
    except subprocess.CalledProcessError as e:
        LOGGER.error(f"Terraform apply failed: {e.stderr}")
        raise Exception(f"Terraform apply failed: {e.stderr}") from e
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
