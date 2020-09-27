# AWS Nuker

AWS Nuker is a command line tool to destroy all resources in a given Amazon Web Services service (e.g. EC2, S3, etc.).

## Requirements
* Ruby 2.6.x

## Usage
**Make sure you `bundle` first before proceeding.**
```
# Destroy all S3 buckets and objects inside them for S3 in us-east-1 region with deprecated-staging profile
bundle exec aws_nuker.rb -p deprecated-staging -r us-east-1 -s s3

# Dry run for the same command
bundle exec aws_nuker.rb -p deprecated-staging -r us-east-1 -s s3 -d

# With full option names
bundle exec aws_nuker.rb --profile deprecated-staging --region us-east-1 --service s3

# Help message
bundle exec aws_nuker.rb -h
```

## Supported AWS Services
|     | Service Name To Use | Note                                                                                                                   |
|-----|-------------------|------------------------------------------------------------------------------------------------------------------------|
| EC2 | ec2               | Termination protection will be disabled automatically.                                                                 |
| S3  | s3                | Only delete empty buckets. For buckets with objects, an object lifecycle config with 1 day expiration will be created. |
