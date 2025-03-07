# Contributing Guide

Thank you for your interest in contributing to the Atmos-managed AWS infrastructure project! This guide will help you get started with the development process.

## Code of Conduct

Please be respectful and considerate of others when contributing to this project. We value constructive feedback and appreciate your help in making this project better.

## Ways to Contribute

There are many ways to contribute to this project:

- Adding new infrastructure components
- Improving existing components
- Enhancing documentation
- Creating examples
- Reporting bugs
- Suggesting features
- Reviewing pull requests

## Getting Started

1. **Fork the repository**

   Click the "Fork" button at the top right of the repository on GitHub.

2. **Clone your fork**

   ```bash
   git clone https://github.com/your-username/tf-atmos.git
   cd tf-atmos
   ```

3. **Set up the development environment**

   Follow the [installation guide](installation.md) to set up all required tools.
   
   The project uses a `.env` file in the root directory to define tool versions:
   ```bash
   # Review the .env file content to understand required tool versions
   cat .env
   ```

4. **Create a branch for your changes**

   ```bash
   #!/usr/bin/env bash
   git checkout -b feature/your-feature-name
   ```

## Development Workflow

### Adding a New Component

1. Follow the [component creation guide](terraform-component-creation-guide.md)
2. Create necessary component files following our [code style guidelines](../GUIDELINES.md)
3. Add documentation in README.md
4. Create examples in the examples directory
5. Update the component catalog

### Modifying an Existing Component

1. Make your changes to the component
2. Update documentation as necessary
3. Test the changes in a development environment
4. Update examples if needed

### Documentation Updates

1. Identify documentation that needs improvement
2. Make your changes, ensuring clarity and correctness
3. Add diagrams where appropriate using Mermaid

## Testing Your Changes

1. **Run Validation**

   ```bash
   atmos workflow lint
   atmos workflow validate
   ```

2. **Test in a Development Environment**

   ```bash
   # Create a test environment if needed
   atmos workflow onboard-environment tenant=mycompany account=dev environment=test-pr vpc_cidr=10.99.0.0/16
   
   # Apply your specific component
   atmos terraform apply your-component -s mycompany-dev-test-pr
   ```

3. **Verify Resources**

   Verify that AWS resources are created correctly and match your expected configuration.

## Submitting Your Contribution

1. **Commit Your Changes**

   ```bash
   git add .
   git commit -m "Add detailed description of your changes"
   ```

2. **Push to Your Fork**

   ```bash
   git push origin feature/your-feature-name
   ```

3. **Create a Pull Request**

   - Go to the original repository
   - Click "New Pull Request"
   - Select "compare across forks"
   - Choose your fork and branch
   - Fill out the PR template with details about your changes

4. **Pull Request Reviews**

   - Respond to feedback from reviewers
   - Make requested changes if needed
   - Ensure all CI checks pass

## Pull Request Guidelines

- Be specific about what your PR addresses
- Include relevant issue numbers if applicable
- Describe the purpose of your changes
- Explain testing you've performed
- Ensure your PR follows project coding standards
- Include documentation updates if needed

## Commit Message Guidelines

- Use clear, descriptive commit messages
- Start with a verb in present tense (e.g., "Add feature" not "Added feature")
- Keep the first line under 50 characters
- Include a more detailed description if necessary
- Reference issues with "Fixes #123" or "Relates to #456" if applicable

## Style Guidelines

- Follow Terraform style guidelines:
  - Use 2 spaces for indentation
  - Use snake_case for naming variables and resources
  - Use clear, descriptive names
  - Include comments for complex logic

- Follow YAML style guidelines for stack configurations:
  - Use 2 spaces for indentation
  - Use descriptive key names
  - Organize configuration logically
  
- Follow Shell script guidelines:
  - Use `#!/usr/bin/env bash` shebang for portability
  - Source the `.env` file for tool version information
  - Use environment variables with defaults for configurable values
  - Implement platform detection for cross-platform compatibility

## Documentation Guidelines

- Use clear, concise language
- Include diagrams for complex architectures
- Provide examples where helpful
- Keep documentation up-to-date with code changes

## Getting Help

If you have questions or need help with your contribution, you can:

- Create an issue for discussion
- Ask for clarification in your pull request
- Reach out to the maintainers

## Thank You

Your contributions are what make this project better for everyone. We greatly appreciate your time and effort!