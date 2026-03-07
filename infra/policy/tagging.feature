Feature: Mandatory Tagging Policy
  In order to maintain resource traceability and cost allocation
  As an infrastructure administrator
  I want to ensure all taggable resources have mandatory tags

  Scenario Outline: Ensure mandatory tags are present on key resources
    Given I have <resource_type> defined
    Then it must contain tags
    And it must contain <tag_name>
    And its value must contain <tag_value>

    Examples:
      | resource_type          | tag_name  | tag_value  |
      | aws_s3_bucket          | Project   | infra-lab  |
      | aws_s3_bucket          | ManagedBy | terraform  |
      | aws_instance           | Project   | infra-lab  |
      | aws_instance           | ManagedBy | terraform  |
      | aws_vpc                | Project   | infra-lab  |
      | aws_vpc                | ManagedBy | terraform  |
      | aws_subnet             | Project   | infra-lab  |
      | aws_subnet             | ManagedBy | terraform  |
      | aws_security_group     | Project   | infra-lab  |
      | aws_security_group     | ManagedBy | terraform  |
      | aws_iam_role           | Project   | infra-lab  |
      | aws_iam_role           | ManagedBy | terraform  |
      | aws_kms_key            | Project   | infra-lab  |
      | aws_kms_key            | ManagedBy | terraform  |
      | aws_dynamodb_table     | Project   | infra-lab  |
      | aws_dynamodb_table     | ManagedBy | terraform  |
