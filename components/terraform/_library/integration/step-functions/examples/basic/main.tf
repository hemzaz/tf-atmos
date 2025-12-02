module "workflow" {
  source = "../../"

  name_prefix        = "example"
  state_machine_name = "simple-workflow"

  definition = jsonencode({
    Comment = "Simple workflow example"
    StartAt = "HelloWorld"
    States = {
      HelloWorld = {
        Type   = "Pass"
        Result = "Hello World!"
        End    = true
      }
    }
  })

  enable_logging      = true
  enable_xray_tracing = true

  tags = {
    Environment = "dev"
  }
}
