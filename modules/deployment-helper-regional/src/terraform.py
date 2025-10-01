import os
import logging
import subprocess
from urllib.request import urlretrieve
from zipfile import ZipFile

LOGGER = logging.getLogger(__name__)


def install(version, location):
    """
    Download and install Terraform binary to the specified location.

    Args:
        version (str): Terraform version to download (e.g., "1.11.4")
        location (str): Directory path where Terraform should be installed

    Returns:
        str: Path to the installed Terraform binary

    Raises:
        Exception: If download or extraction fails
    """
    tf_binary = os.path.join(location, "terraform")

    # Check if Terraform is already installed at this location
    if os.path.exists(tf_binary):
        LOGGER.info(f'Terraform binary already exists at "{tf_binary}".')
        return tf_binary

    LOGGER.info(f'Installing Terraform version {version} to "{tf_binary}".')
    os.makedirs(location, exist_ok=True)
    terraform_url = f"https://releases.hashicorp.com/terraform/{version}/terraform_{version}_linux_amd64.zip"
    zip_path = os.path.join(location, "terraform.zip")
    try:
        LOGGER.info(f'Downloading Terraform from "{terraform_url}" to "{zip_path}".')
        urlretrieve(terraform_url, zip_path)
        LOGGER.info(f'Extracting Terraform from "{zip_path}" to "{location}".')
        with ZipFile(zip_path, "r") as zip_ref:
            zip_ref.extractall(location)
        os.remove(zip_path)
        # Make binary executable
        os.chmod(tf_binary, 0o755)
        LOGGER.info(f'Successfully installed Terraform to "{tf_binary}".')
        return tf_binary
    except Exception as e:
        LOGGER.error(f"Failed to install Terraform: {str(e)}")
        # Clean up on failure
        if os.path.exists(zip_path):
            os.remove(zip_path)
        if os.path.exists(tf_binary):
            os.remove(tf_binary)
        raise Exception(f"Terraform installation failed: {str(e)}") from e


def init(tf_binary, bucket=None, key=None, region=None, additional_args=None):
    """
    Run terraform init with optional backend configuration.

    Args:
        tf_binary (str): Path to the Terraform binary
        bucket (str, optional): S3 bucket name for backend state storage
        key (str, optional): S3 key path for the state file
        region (str, optional): AWS region for the S3 backend
        additional_args (list, optional): Additional arguments to pass to terraform init

    Returns:
        subprocess.CompletedProcess: The result of the terraform init command

    Raises:
        Exception: If terraform init fails
    """
    cmd = [tf_binary, "init", "-no-color"]
    if bucket:
        cmd.append(f"-backend-config=bucket={bucket}")
    if key:
        cmd.append(f"-backend-config=key={key}")
    if region:
        cmd.append(f"-backend-config=region={region}")
    if additional_args:
        cmd.extend(additional_args)
    LOGGER.info(f"Running terraform init with command: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        LOGGER.info(f"Terraform init stdout: {result.stdout}")
        if result.stderr:
            LOGGER.info(f"Terraform init stderr: {result.stderr}")
        return result
    except subprocess.CalledProcessError as e:
        LOGGER.error(f"Terraform init failed: {e.stderr}")
        raise Exception(f"Terraform init failed: {e.stderr}") from e


def plan(tf_binary, var_file=None, destroy=False, out_file=None, additional_args=None):
    """
    Run terraform plan to show what changes will be made.

    Args:
        tf_binary (str): Path to the Terraform binary
        var_file (str, optional): Path to variables file (e.g., terraform.tfvars.json)
        destroy (bool, optional): Whether to plan for destroy mode. Default: False
        out_file (str, optional): Path to output the plan file. If not provided, defaults to "tfplan"
        additional_args (list, optional): Additional arguments to pass to terraform plan

    Returns:
        tuple: (subprocess.CompletedProcess, str) - The result and the plan file path

    Raises:
        Exception: If terraform plan fails
    """
    cmd = [tf_binary, "plan", "-no-color"]
    if out_file:
        cmd.append(f"-out={out_file}")
    if var_file:
        cmd.append(f"-var-file={var_file}")
    if destroy:
        cmd.append("-destroy")
    if additional_args:
        cmd.extend(additional_args)
    action = "destroy plan" if destroy else "plan"
    LOGGER.info(f"Running terraform plan ({action}) with command: {' '.join(cmd)}")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        LOGGER.info(f"Terraform plan output:\n{result.stdout}")
        if result.stderr:
            LOGGER.info(f"Terraform plan stderr: {result.stderr}")
        return result

    except subprocess.CalledProcessError as e:
        LOGGER.error(f"Terraform plan failed: {e.stderr}")
        raise Exception(f"Terraform plan failed: {e.stderr}") from e


def apply(
    tf_binary,
    plan_file=None,
    var_file=None,
    destroy=False,
    auto_approve=True,
    additional_args=None,
):
    """
    Run terraform apply with optional parameters.

    Args:
        tf_binary (str): Path to the Terraform binary
        plan_file (str, optional): Path to a plan file to apply. If provided, var_file, destroy, and auto_approve are ignored
        var_file (str, optional): Path to variables file (e.g., terraform.tfvars.json). Ignored if plan_file is provided
        destroy (bool, optional): Whether to run in destroy mode. Default: False. Ignored if plan_file is provided
        auto_approve (bool, optional): Whether to auto-approve changes. Default: True. Ignored if plan_file is provided
        additional_args (list, optional): Additional arguments to pass to terraform apply

    Returns:
        subprocess.CompletedProcess: The result of the terraform apply command

    Raises:
        Exception: If terraform apply fails
    """
    cmd = [tf_binary, "apply", "-no-color"]
    if plan_file:
        # When using a plan file, we only need the plan file argument
        cmd.append(plan_file)
        action = "apply from plan file"
        LOGGER.info(f"Running terraform apply with plan file: {plan_file}")
    else:
        # Traditional apply with individual parameters
        if auto_approve:
            cmd.append("-auto-approve")
        if var_file:
            cmd.append(f"-var-file={var_file}")
        if destroy:
            cmd.append("-destroy")
        action = "destroy" if destroy else "apply"

    if additional_args:
        cmd.extend(additional_args)

    LOGGER.info(f"Running terraform apply ({action}) with command: {' '.join(cmd)}")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
        LOGGER.info(f"Terraform apply stdout: {result.stdout}")
        if result.stderr:
            LOGGER.info(f"Terraform apply stderr: {result.stderr}")
        return result

    except subprocess.CalledProcessError as e:
        LOGGER.error(f"Terraform apply failed: {e.stderr}")
        raise Exception(f"Terraform apply failed: {e.stderr}") from e
