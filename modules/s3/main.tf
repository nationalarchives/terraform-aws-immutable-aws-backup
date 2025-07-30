resource "aws_s3_bucket" "bucket" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = var.versioning
  }
}

resource "aws_s3_bucket_logging" "bucket" {
  count = var.log_bucket == "" ? 0 : 1

  bucket = aws_s3_bucket.bucket.id

  target_bucket = var.log_bucket
  target_prefix = "${aws_s3_bucket.bucket.id}/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kms" {
  count = var.kms_key_arn != "" ? 1 : 0

  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3" {
  count = var.kms_key_arn == "" ? 1 : 0

  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
  skip_destroy            = var.bpa_skip_destroy
}

resource "aws_s3_bucket_policy" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  policy = templatefile("${path.module}/templates/secure-transport.json", {
    bucket_name = aws_s3_bucket.bucket.id,
  })
  depends_on = [aws_s3_bucket_public_access_block.bucket]
}

resource "aws_s3_bucket_ownership_controls" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    object_ownership = var.object_ownership
  }
}
