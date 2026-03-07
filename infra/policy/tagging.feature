Feature: Mandatory Tagging Policy
  In order to maintain resource traceability
  As an infrastructure administrator
  I want to ensure all resources have mandatory tags

  Scenario: Ensure Project and ManagedBy tags are present
    Given I have resource that supports tags
    Then it must contain Project
    And its value must match infra-lab
    And it must contain ManagedBy
    And its value must match terraform
