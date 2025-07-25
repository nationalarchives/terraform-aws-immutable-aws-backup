locals {
  # https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-region-billing-codes.html
  aws_region_abbreviations = {
    us-east-1      = "use1"
    us-east-2      = "use2"
    us-west-1      = "usw1"
    us-west-2      = "usw2"
    ca-central-1   = "can1"
    ca-west-1      = "can2"
    mx-central-1   = "mxc1"
    af-south-1     = "afs1"
    ap-east-1      = "ape1"
    ap-northeast-1 = "apn1"
    ap-northeast-2 = "apn2"
    ap-northeast-3 = "apn3"
    ap-southeast-1 = "aps1"
    ap-southeast-2 = "aps2"
    ap-south-1     = "aps3"
    ap-southeast-3 = "aps4"
    ap-south-2     = "aps5"
    ap-southeast-4 = "aps6"
    ap-southeast-5 = "aps7"
    ap-southeast-7 = "aps8"
    eu-west-1      = "eu"
    eu-central-1   = "euc1"
    eu-central-2   = "euc2"
    eu-west-2      = "euw2"
    eu-west-3      = "euw3"
    eu-north-1     = "eun1"
    eu-south-1     = "eus1"
    eu-south-2     = "eus2"
    il-central-1   = "ilc1"
    me-central-1   = "mec1"
    me-south-1     = "mes1"
    sa-east-1      = "sae1"
  }
}
