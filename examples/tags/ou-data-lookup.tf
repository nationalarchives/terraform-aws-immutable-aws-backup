module "ou_data_lookup" {
  source  = "nationalarchives/organizations-ous-by-path/aws"
  version = "1.2.0"

  name_path_delimiter = " / "
}
