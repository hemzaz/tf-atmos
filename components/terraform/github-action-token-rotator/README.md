# github-action-token-rotator

A scheduled Lambda function that keeps a fresh GitHub Actions runner registration token in an SSM
SecureString for `github-runners`. It does the job of Cloud Posse `aws-github-action-token-rotator`
and keeps its input names. The difference is plain resources and an in-repo function
(`functions/token-rotator`, Node.js 22, no dependencies). The upstream module runs nodejs16.x
from a package in Cloud Posse's own bucket, and puts the App's private key in a Lambda
environment variable, and so in the state. Here the function reads the key from SSM at run time.

## Wiring

- Catalog: `github-action-token-rotator/defaults`, with one instance per account and region that
  runs `github-runners`, deployed before them.
- The token parameter (`parameter_store_token_path`) is created here. The function overwrites it
  every `schedule_expression` (30 minutes by default). `github-runners` reads it at boot
  (`registration_token_parameter_name`, the `.token_parameter_name` output).
- `github_repository_name` set: the token registers repository runners for
  `<github_org_name>/<github_repository_name>`. This input is not in Cloud Posse's component, which
  registers organization runners only. A user account has no organization runners.

## One-time GitHub App setup (owner)

1. Create a GitHub App (Settings → Developer settings → GitHub Apps), with no webhook and no
   callback.
   - Repository permissions: **Administration: Read and write**. That is the runner
     registration-token API for repository runners. For organization runners, use
     **Self-hosted runners: Read and write** instead.
   - **Metadata: Read** is implied.
   - No other permission.
2. Install it on the repository only. Note the App ID and the installation ID (the number at the
   end of the installation's URL). These are not secrets: set them as `github_app_id` and
   `github_app_installation_id`.
3. Generate a private key and store it in SSM in each account that runs runners, encrypted with
   `kms/main`, then delete the downloaded file. It never goes in the repository or a stack file.

   ```bash
   aws ssm put-parameter --name /github/runners/app-private-key --type SecureString \
     --key-id alias/<kms/main alias> --value file://app.private-key.pem
   ```
4. After the first apply, invoke the function once (`aws lambda invoke --function-name
   <function_name output> /dev/null`), so the token exists before the first scheduled run.

## Notes

- The private key parameter is not managed here, so its value never enters the state. The
  function may read only that parameter and write only the token parameter, and it may use the
  key only through SSM.
- A registration token is valid for an hour and only registers a runner. A runner that has
  already registered keeps working after the token rotates.
- Rotation failures appear only in the function's log group, which is KMS-encrypted. A runner that
  boots with an expired token fails to register.
- The function's logic is tested with `node --test functions/token-rotator/`.
