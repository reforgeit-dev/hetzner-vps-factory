terraform {
  backend "s3" {
    bucket       = "<your-bucket>"       # S3 bucket for state storage
    key          = "<your-state-key>"     # e.g. "hetzner/prod/hel1/myproject"
    region       = "eu-west-1"           # AWS region for the bucket
    use_lockfile = true
    profile      = "<your-profile>"      # AWS CLI profile name
  }
}