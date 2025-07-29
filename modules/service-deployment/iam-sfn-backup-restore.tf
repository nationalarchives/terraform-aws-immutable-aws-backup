#
# Role for the Backup Restore Step Function to assume
#
module "backup_restore_sfn_role" {
  source = "../iam-role"

  name = "${local.restore_state_machine_name}-sfn"
  assume_role_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect = "Allow"
        Principal : {
          Service : "states.amazonaws.com"
        }
        Action : "sts:AssumeRole",
        Condition : {
          StringEquals : {
            "aws:SourceAccount" : var.current.account_id
          }
        }
      }
    ]
  })
  inline_policy = jsonencode({
    Version : "2012-10-17"
    Statement : local.step_function_role_policy_statements
  })
}
