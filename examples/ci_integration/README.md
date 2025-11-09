# CI/CD Integration for Continuous Fuzzing

This directory contains examples for integrating AFL fuzzing into your CI/CD pipeline.

## Supported Platforms

- GitHub Actions
- GitLab CI/CD
- Jenkins (see jenkins/ directory)
- CircleCI
- Travis CI

## Overview

Continuous fuzzing helps you:
- Find bugs before they reach production
- Maintain security over time
- Automate vulnerability discovery
- Track fuzzing coverage

## GitHub Actions Setup

### Quick Start

1. Copy the workflow file:
```bash
cp .github_workflows_fuzz.yml .github/workflows/fuzz.yml
```

2. Update target names in the workflow:
```yaml
strategy:
  matrix:
    target: [fuzz_target_1, fuzz_target_2]  # Your fuzz targets
```

3. Commit and push:
```bash
git add .github/workflows/fuzz.yml
git commit -m "Add continuous fuzzing"
git push
```

### Workflow Features

#### Quick Fuzz on PRs
- Runs on every pull request
- 5-minute quick fuzz test
- Fails if crashes found
- Provides fast feedback

#### Extended Fuzz (Scheduled)
- Runs daily at 2 AM UTC
- 1-hour fuzzing session per target
- Caches corpus between runs
- Creates issues for crashes

#### Manual Trigger
- Fuzz on-demand via GitHub UI
- Custom duration parameter
- Useful for testing fixes

### Configuration

```yaml
# Adjust fuzzing duration (seconds)
timeout 3600 cargo afl fuzz ...  # 1 hour

# Change schedule
schedule:
  - cron: '0 2 * * *'  # Daily at 2 AM

# Add more targets
strategy:
  matrix:
    target: [target1, target2, target3]
```

## GitLab CI/CD Setup

### Quick Start

1. Copy the CI file:
```bash
cp .gitlab-ci.yml .gitlab-ci.yml
```

2. Create schedule:
   - Go to CI/CD > Schedules
   - Create new schedule
   - Set to run daily

3. (Optional) Set up crash reporting:
```bash
# In GitLab Settings > CI/CD > Variables
GITLAB_API_TOKEN=<your-token>
```

### Pipeline Stages

1. **Build**: Compile fuzz targets
2. **Fuzz**: Run fuzzing (quick or extended)
3. **Analyze**: Check for crashes, minimize inputs

### Features

- Parallel fuzzing for multiple targets
- Corpus caching between runs
- Automatic crash minimization
- Issue creation for crashes
- Detailed reports

## Jenkins Integration

### Jenkinsfile

```groovy
pipeline {
    agent any

    environment {
        CARGO_HOME = "${WORKSPACE}/.cargo"
    }

    stages {
        stage('Install AFL') {
            steps {
                sh 'cargo install afl'
            }
        }

        stage('Build Fuzz Targets') {
            steps {
                sh 'cargo afl build --release --features fuzzing'
            }
        }

        stage('Fuzz') {
            parallel {
                stage('Target 1') {
                    steps {
                        sh '''
                            timeout 3600 cargo afl fuzz \
                                -i corpus/initial \
                                -o findings1 \
                                target/release/fuzz_target_1 || true
                        '''
                    }
                }
                stage('Target 2') {
                    steps {
                        sh '''
                            timeout 3600 cargo afl fuzz \
                                -i corpus/initial \
                                -o findings2 \
                                target/release/fuzz_target_2 || true
                        '''
                    }
                }
            }
        }

        stage('Analyze') {
            steps {
                sh '''
                    for dir in findings*/crashes; do
                        if [ -d "$dir" ]; then
                            echo "Crashes in $dir:"
                            find "$dir" -type f ! -name 'README.txt'
                        fi
                    done
                '''
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'findings*/**', allowEmptyArchive: true
        }
        failure {
            emailext (
                subject: "Fuzzing found crashes in ${env.JOB_NAME}",
                body: "Check ${env.BUILD_URL} for details",
                to: "security@example.com"
            )
        }
    }
}
```

## CircleCI Integration

### .circleci/config.yml

```yaml
version: 2.1

jobs:
  fuzz:
    docker:
      - image: rust:latest
    steps:
      - checkout
      - run:
          name: Install AFL
          command: cargo install afl
      - run:
          name: Build
          command: cargo afl build --release --features fuzzing
      - run:
          name: Fuzz
          command: |
            timeout 3600 cargo afl fuzz \
              -i corpus/initial \
              -o findings \
              target/release/fuzz_target || true
      - run:
          name: Check Crashes
          command: |
            if [ -d findings/crashes ]; then
              find findings/crashes -type f ! -name 'README.txt' | wc -l
            fi
      - store_artifacts:
          path: findings

workflows:
  version: 2
  daily-fuzz:
    triggers:
      - schedule:
          cron: "0 2 * * *"
          filters:
            branches:
              only: main
    jobs:
      - fuzz
```

## Best Practices

### 1. Start Small

Begin with short fuzzing sessions:
```yaml
# PR: 5 minutes
timeout 300 cargo afl fuzz ...

# Nightly: 1 hour
timeout 3600 cargo afl fuzz ...

# Weekly: 8 hours
timeout 28800 cargo afl fuzz ...
```

### 2. Cache Wisely

Cache corpus but not findings:
```yaml
cache:
  paths:
    - corpus/       # Cache
    - .cargo/       # Cache
    - target/       # Cache
    # findings/ - Don't cache, analyze each run
```

### 3. Fail Fast

Make PRs fail if crashes found:
```bash
if [ $crash_count -gt 0 ]; then
  echo "Crashes found!"
  exit 1
fi
```

### 4. Parallel Fuzzing

Run multiple targets in parallel:
```yaml
strategy:
  matrix:
    target: [fuzz1, fuzz2, fuzz3]
```

### 5. Corpus Management

Sync corpus across runs:
```bash
# Save interesting inputs
cp findings/queue/* corpus/

# Minimize corpus periodically
cargo afl cmin -i corpus -o corpus_minimized ./target
```

### 6. Resource Limits

Set appropriate limits:
```yaml
timeout: 7200          # 2 hours max
resources:
  limits:
    memory: 2Gi        # 2 GB memory
    cpu: "2"           # 2 CPU cores
```

## Monitoring and Alerts

### Slack Notifications

```bash
# In your CI script
if [ $crashes -gt 0 ]; then
  curl -X POST $SLACK_WEBHOOK -d "{
    \"text\": \"🐛 Fuzzing found $crashes crashes!\"
  }"
fi
```

### Email Alerts

```yaml
# GitHub Actions
- name: Send email
  uses: dawidd6/action-send-mail@v3
  if: failure()
  with:
    server_address: smtp.gmail.com
    server_port: 465
    username: ${{secrets.MAIL_USERNAME}}
    password: ${{secrets.MAIL_PASSWORD}}
    subject: Fuzzing found crashes
    body: Check the workflow run for details
```

### Custom Dashboards

Create a dashboard showing:
- Crashes found over time
- Code coverage trends
- Fuzzing performance metrics
- Time to discover bugs

## Security Considerations

### 1. Sensitive Data

Don't commit crashes with sensitive data:
```yaml
# .gitignore
findings/
crashes/
*.crash
```

### 2. Access Control

Restrict who can:
- View fuzzing results
- Download crash files
- Modify fuzzing configs

### 3. Secure Reporting

Use private issues for crashes:
```yaml
# GitHub Actions
labels: ['security', 'private']
```

### 4. Token Security

Use secrets for API tokens:
```yaml
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Troubleshooting

### AFL Not Finding Bugs

1. **Check corpus quality**: Use real-world inputs
2. **Run longer**: Some bugs take time to find
3. **Try dictionaries**: Add format-specific keywords
4. **Verify instrumentation**: Ensure AFL is actually running

### Timeouts

Increase timeout or reduce input size:
```yaml
timeout 7200 cargo afl fuzz -t 1000 ...
```

### Memory Issues

Limit memory usage:
```bash
cargo afl fuzz -m 512 ...  # 512 MB limit
```

### Cache Misses

Verify cache keys are correct:
```yaml
cache:
  key: ${{ runner.os }}-${{ hashFiles('**/Cargo.lock') }}
```

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitLab CI Documentation](https://docs.gitlab.com/ee/ci/)
- [AFL Documentation](http://lcamtuf.coredump.cx/afl/)
- [Rust Fuzzing Book](https://rust-fuzz.github.io/book/)

## Examples

See the workflow files:
- `.github_workflows_fuzz.yml` - GitHub Actions
- `.gitlab-ci.yml` - GitLab CI
- `jenkins/` - Jenkins examples

For local testing, use:
```bash
act -j quick-fuzz  # GitHub Actions locally
gitlab-runner exec docker fuzz:quick  # GitLab locally
```
