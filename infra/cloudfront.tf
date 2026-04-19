# ─────────────────────────────────────────────────────────────────────────────
# CodeGuard — CloudFront distribution
# File: infra/cloudfront.tf
#
# Serves the Next.js static export over HTTPS with global edge caching.
#
# Origin: S3 website endpoint (HTTP only) — required for index.html resolution.
#   The website endpoint resolves /product/ → product/index.html automatically.
#   The REST endpoint does exact key lookups only and returns NoSuchKey for paths.
#
# Custom error responses: 403 and 404 from S3 are rewritten to /index.html with
#   HTTP 200 so Next.js client-side routing works on hard refreshes.
#
# HTTPS: Uses the CloudFront default certificate (*.cloudfront.net). For a
#   custom domain, add an ACM certificate and aliases block (Bonus A).
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Logical name for the S3 origin — used in default_cache_behavior target
  s3_origin_id = "S3WebsiteOrigin"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${local.name} static frontend"
  price_class         = "PriceClass_100"  # US, Canada, Europe only (cheapest tier)

  # ─── Origin — S3 website endpoint ─────────────────────────────────────────
  # Use custom_origin_config (not s3_origin_config) because this is the
  # *website* endpoint which behaves like an HTTP server, not an S3 REST API.
  origin {
    domain_name = aws_s3_bucket_website_configuration.frontend.website_endpoint
    origin_id   = local.s3_origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"   # S3 website endpoint is HTTP only
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ─── Default cache behaviour ───────────────────────────────────────────────
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"  # Upgrade HTTP → HTTPS at edge

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 3600    # 1 hour default cache
    max_ttl     = 86400   # 24 hours max cache
  }

  # ─── Custom error responses ────────────────────────────────────────────────
  # S3 returns 403 (AccessDenied) for missing keys when public access is enabled,
  # and 404 for explicitly missing objects. Both are rewritten to /index.html
  # with 200 so Next.js handles the route client-side.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  # ─── Geo restriction ──────────────────────────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # ─── TLS certificate ──────────────────────────────────────────────────────
  # Uses the default *.cloudfront.net certificate. No ACM cert required.
  # For a custom domain, replace with:
  #   acm_certificate_arn      = var.acm_cert_arn
  #   ssl_support_method       = "sni-only"
  #   minimum_protocol_version = "TLSv1.2_2021"
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}