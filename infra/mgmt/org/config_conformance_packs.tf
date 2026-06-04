####
# Organization Config Conformance Packs - E03-S012
#
# Deploys organization-wide AWS Config conformance packs for automated
# compliance monitoring. These provide detective controls that complement
# the preventative SCPs defined in scps.tf.
#
# Conformance packs are deployed to all member accounts automatically.
####

# Organization Conformance Pack: Security Baseline
# Covers encryption, public access, logging, and IAM best practices
resource "aws_config_organization_conformance_pack" "security_baseline" {
  name = "infra-lab-security-baseline"

  # Exclude accounts that don't have AWS Config Recorder enabled.
  # Management account and test-env are not managed by Control Tower's
  # Config setup. They will be onboarded separately.
  excluded_accounts = [
    "551452024305", # Management account
    "970353898303", # test-env account
  ]

  template_body = <<-EOT
    Resources:
      S3BucketEncryption:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-server-side-encryption-enabled
          Description: Checks that S3 buckets have server-side encryption enabled.
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED
          Scope:
            ComplianceResourceTypes:
              - AWS::S3::Bucket

      S3BucketPublicReadProhibited:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-public-read-prohibited
          Description: Checks that S3 buckets do not allow public read access.
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_PUBLIC_READ_PROHIBITED
          Scope:
            ComplianceResourceTypes:
              - AWS::S3::Bucket

      S3BucketPublicWriteProhibited:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-public-write-prohibited
          Description: Checks that S3 buckets do not allow public write access.
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_PUBLIC_WRITE_PROHIBITED
          Scope:
            ComplianceResourceTypes:
              - AWS::S3::Bucket

      S3BucketVersioningEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-versioning-enabled
          Description: Checks that S3 buckets have versioning enabled.
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_VERSIONING_ENABLED
          Scope:
            ComplianceResourceTypes:
              - AWS::S3::Bucket

      S3BucketLoggingEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: s3-bucket-logging-enabled
          Description: Checks that S3 buckets have access logging enabled.
          Source:
            Owner: AWS
            SourceIdentifier: S3_BUCKET_LOGGING_ENABLED
          Scope:
            ComplianceResourceTypes:
              - AWS::S3::Bucket

      EncryptedVolumes:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: encrypted-volumes
          Description: Checks that EBS volumes are encrypted.
          Source:
            Owner: AWS
            SourceIdentifier: ENCRYPTED_VOLUMES
          Scope:
            ComplianceResourceTypes:
              - AWS::EC2::Volume

      RdsEncryptionEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: rds-storage-encrypted
          Description: Checks that RDS instances have storage encryption enabled.
          Source:
            Owner: AWS
            SourceIdentifier: RDS_STORAGE_ENCRYPTED
          Scope:
            ComplianceResourceTypes:
              - AWS::RDS::DBInstance

      CloudTrailEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cloudtrail-enabled
          Description: Checks that CloudTrail is enabled in the account.
          Source:
            Owner: AWS
            SourceIdentifier: CLOUD_TRAIL_ENABLED
          MaximumExecutionFrequency: TwentyFour_Hours

      CloudTrailEncryptionEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: cloud-trail-encryption-enabled
          Description: Checks that CloudTrail logs are encrypted with KMS.
          Source:
            Owner: AWS
            SourceIdentifier: CLOUD_TRAIL_ENCRYPTION_ENABLED
          MaximumExecutionFrequency: TwentyFour_Hours

      RootAccountMfaEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: root-account-mfa-enabled
          Description: Checks that the root account has MFA enabled.
          Source:
            Owner: AWS
            SourceIdentifier: ROOT_ACCOUNT_MFA_ENABLED
          MaximumExecutionFrequency: TwentyFour_Hours

      IamRootAccessKeyCheck:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: iam-root-access-key-check
          Description: Checks that the root account does not have access keys.
          Source:
            Owner: AWS
            SourceIdentifier: IAM_ROOT_ACCESS_KEY_CHECK
          MaximumExecutionFrequency: TwentyFour_Hours

      IamPasswordPolicy:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: iam-password-policy
          Description: Checks that the account password policy meets minimum requirements.
          Source:
            Owner: AWS
            SourceIdentifier: IAM_PASSWORD_POLICY
          MaximumExecutionFrequency: TwentyFour_Hours

      MultiRegionCloudTrailEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: multi-region-cloudtrail-enabled
          Description: Checks that multi-region CloudTrail is enabled.
          Source:
            Owner: AWS
            SourceIdentifier: MULTI_REGION_CLOUD_TRAIL_ENABLED
          MaximumExecutionFrequency: TwentyFour_Hours

      VpcFlowLogsEnabled:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: vpc-flow-logs-enabled
          Description: Checks that VPC Flow Logs are enabled.
          Source:
            Owner: AWS
            SourceIdentifier: VPC_FLOW_LOGS_ENABLED
          MaximumExecutionFrequency: TwentyFour_Hours

      RestrictedSsh:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: restricted-ssh
          Description: Checks that security groups do not allow unrestricted SSH access.
          Source:
            Owner: AWS
            SourceIdentifier: INCOMING_SSH_DISABLED
          Scope:
            ComplianceResourceTypes:
              - AWS::EC2::SecurityGroup

      RequiredTagsEc2:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: required-tags-ec2
          Description: Checks that EC2 instances have required tags (Project, ManagedBy, Environment, Owner).
          Source:
            Owner: AWS
            SourceIdentifier: REQUIRED_TAGS
          Scope:
            ComplianceResourceTypes:
              - AWS::EC2::Instance
          InputParameters:
            tag1Key: Project
            tag2Key: ManagedBy
            tag3Key: Environment
            tag4Key: Owner

      RequiredTagsS3:
        Type: AWS::Config::ConfigRule
        Properties:
          ConfigRuleName: required-tags-s3
          Description: Checks that S3 buckets have required tags (Project, ManagedBy, Environment, Owner).
          Source:
            Owner: AWS
            SourceIdentifier: REQUIRED_TAGS
          Scope:
            ComplianceResourceTypes:
              - AWS::S3::Bucket
          InputParameters:
            tag1Key: Project
            tag2Key: ManagedBy
            tag3Key: Environment
            tag4Key: Owner
  EOT

  depends_on = [aws_organizations_organization.org]
}
