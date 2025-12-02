module "glue_catalog" {
  source = "../.."

  database_name        = "dev_analytics"
  database_description = "Development analytics database"

  crawlers = {
    sample_data = {
      description = "Crawl sample data"
      s3_targets = [{
        path = "s3://example-bucket/data/"
      }]
    }
  }

  s3_data_locations = [
    "arn:aws:s3:::example-bucket"
  ]

  tags = {
    Environment = "development"
    Example     = "basic"
  }
}

output "database_name" {
  value = module.glue_catalog.database_name
}
