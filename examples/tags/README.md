# Immutable AWS Backup Terraform Module

## Local Development - Terraform
from within this subdirectory:
```
terraform init -backend-config=bucket={YOUR_TERRAFORM_STATE_BUCKET} -backend-config=key=aws-backups -backend-config=region={YOUR_TERRAFORM_STATE_REGION}
terraform plan
terraform apply
```
