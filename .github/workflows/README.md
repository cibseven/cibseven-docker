# GitHub Actions

1. [Build, test, and publish](./build-test-and-publish-ce.yml) - runs on every push and PR to check image for all 3 environments (tomcat, wildfly, run). Additionally, it publishes the image on new commits to Docker Hub.

2. [Close stale issues](./close-stale-issues.yml) - warns and then closes issues and PRs that have had no activity for a specified amount of time.
