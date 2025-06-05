resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = var.assume_role_policy
}

resource "aws_iam_role_policy" "this" {
  count  = length(var.inline_policy) > 0 ? 1 : 0
  name   = var.name
  role   = aws_iam_role.this.id
  policy = var.inline_policy
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = toset(var.policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.key
}
