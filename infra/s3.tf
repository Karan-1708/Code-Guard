# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — S3 bucket for static frontend
# File: infra/s3.tf
#
# Hosts the Next.js static export (out/ directory). The bucket is configured
# as a static website so the S3 website endpoint can be used as the CloudFront
# origin — this is required for index.html resolution (e.g. /product/ →
# product/index.html) and the custom error response to work correctly.
#
# Public read is enabled because CloudFront reads the bucket as a web origin
# over HTTP. In a production setup you could use an Origin Access Control (OAC)
# policy instead to keep the bucket private — but that requires the REST
# endpoint (not the website endpoint), which breaks the index.html routing.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Bucket ───────────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name}-frontend"
  tags   = local.tags
}

# ─── Disable public access block ──────────────────────────────────────────────
# Required before a bucket policy allowing public read can be applied.
# AWS blocks public policies by default; this resource lifts that restriction.
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

# ─── Bucket policy — allow public GetObject ───────────────────────────────────
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })

  # Must disable public access block before applying a public policy.
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# ─── Static website hosting ───────────────────────────────────────────────────
# Both index_document and error_document point to index.html. This means:
#   - The root URL serves index.html
#   - Any 404 (unknown path) serves index.html — enabling Next.js client-side routing
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document { suffix = "index.html" }
  error_document { key    = "index.html" }
}