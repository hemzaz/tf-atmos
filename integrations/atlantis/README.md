# Atlantis Integration for Atmos

This directory contains the configuration needed to integrate Atlantis with Atmos for automated Terraform workflow execution and pull request automation.

## Features

- Automatic Terraform plan/apply on pull request
- Integration with Atmos workflows
- Component and stack auto-detection
- Pull request commenting with plan results
- Auto-merge capability (optional)
- Parallel execution for faster processing

## Setup Instructions

### Prerequisites

1. A GitHub repository containing your Atmos configuration
2. Permissions to configure webhook on your repository
3. A server to host Atlantis (or Docker for local testing)
4. GitHub personal access token with repo permissions

### Installation

#### Using Docker (Recommended)

1. Build the custom Atlantis image with Atmos:

```bash
docker build -t atlantis-atmos:latest .
```

2. Run the Atlantis server:

```bash
docker run -p 4141:4141 \
  -e GITHUB_TOKEN=<your-github-token> \
  -e GITHUB_WEBHOOK_SECRET=<your-webhook-secret> \
  -e REPO_ALLOWLIST=github.com/your-org/* \
  -v ~/.aws:/home/atlantis/.aws \
  atlantis-atmos:latest
```

3. Configure GitHub webhook to point to your Atlantis server endpoint:
   - URL: `https://your-atlantis-server/events`
   - Content type: `application/json`
   - Secret: Same as `GITHUB_WEBHOOK_SECRET`
   - Events: Select `Pull request`, `Push`, and `Issue comment`

#### Manual Installation

1. Install Atlantis according to the [official documentation](https://www.runatlantis.io/docs/installation-guide.html)
2. Install Atmos in the same environment
3. Copy `atlantis.yaml` to your Atlantis server
4. Configure Atlantis to use the provided repo config

### Configuration

#### Environment Variables

- `GITHUB_TOKEN`: GitHub personal access token
- `GITHUB_WEBHOOK_SECRET`: Secret for verifying GitHub webhooks
- `REPO_ALLOWLIST`: List of repositories Atlantis will respond to

#### AWS Authentication

Atlantis needs access to your AWS credentials. You can provide them by:

1. **Volume mounting**: Mount your AWS credentials directory
2. **IAM roles**: Use IAM roles for EC2 if running on AWS
3. **Environment variables**: Set AWS credentials as environment variables

## Usage

### Creating Pull Requests

When you create a pull request that modifies Terraform files:

1. Atlantis will automatically detect the changes
2. Atlantis will determine the component and stack based on file paths
3. Atlantis will run `atmos terraform plan` and post results as a comment
4. After approval, use comment commands to apply changes

### Atlantis Commands

Comment on the pull request with:

- `atlantis plan`: Manually trigger a plan
- `atlantis apply`: Apply the planned changes (requires approval)
- `atlantis plan -d [component]`: Plan changes for a specific component
- `atlantis apply -d [component]`: Apply changes for a specific component

## Advanced Configuration

### Custom Workflows

You can define custom workflows in the `atlantis.yaml` file:

```yaml
workflows:
  custom:
    plan:
      steps:
      - run: custom-script.sh
      - run: atmos terraform plan $COMPONENT -s $STACK
```

### Security Considerations

- Store your GitHub token and webhook secret securely
- Use least-privilege IAM roles for AWS access
- Implement approval requirements for sensitive environments
- Consider network isolation for your Atlantis server

## Troubleshooting

### Common Issues

1. **Component/stack not detected**: Check the directory structure matches the expected pattern
2. **AWS authentication failures**: Verify credentials are properly configured
3. **Webhook failures**: Check server connectivity and webhook secret

### Logs and Debugging

- Run Atlantis with increased verbosity: `--log-level=debug`
- Check webhook delivery in GitHub repository settings
- Review the pre-workflow hook output in the Atlantis logs

## Additional Resources

- [Atlantis Documentation](https://www.runatlantis.io/docs/)
- [Atmos Documentation](https://atmos.tools/)
- [GitHub Webhook Documentation](https://docs.github.com/en/developers/webhooks-and-events/webhooks/about-webhooks)