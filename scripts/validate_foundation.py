#!/usr/bin/env python3
"""
validate_foundation.py

Validates infra-lab foundations from E01 through E03-S010.
Covers: repo structure, SDLC hygiene, Terraform layout/modules,
local validation commands, and live AWS controls.

Usage:
    python3 scripts/validate_foundation.py [options]

Lint:
    python3 -m flake8 scripts/validate_foundation.py
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

# ---------------------------------------------------------------------------
# Defaults — all sourced from MEMORY.md
# ---------------------------------------------------------------------------
DEFAULT_PROFILE = "infra-lab"
DEFAULT_PRIMARY_REGION = "us-east-1"
DEFAULT_REPLICA_REGION = "us-west-2"
DEFAULT_MGMT_ACCOUNT = "551452024305"
DEFAULT_GD_ADMIN_ACCOUNT = "172134854767"
DEFAULT_SH_ADMIN_ACCOUNT = "881413600100"
DEFAULT_STATE_BUCKET = "infra-lab-tf-state-551452024305"
DEFAULT_LOCK_TABLE = "infra-lab-tf-state-locks"

# ---------------------------------------------------------------------------
# Repo-specific constants — derived from the attached tree
# ---------------------------------------------------------------------------

# Top-level directories that must exist
REQUIRED_REPO_DIRS = ["infra", "app", "docs", "scripts"]

# Top-level files that must exist
REQUIRED_REPO_FILES = ["LICENSE", "SECURITY.md", "CONTRIBUTING.md", "README.md"]

# CODEOWNERS — checked in priority order
CODEOWNERS_CANDIDATES = [
    ".github/CODEOWNERS",
    "CODEOWNERS",
    "docs/CODEOWNERS",
]

# PR template
PR_TEMPLATE_CANDIDATES = [
    ".github/pull_request_template.md",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/PULL_REQUEST_TEMPLATE/pull_request_template.md",
]

# Issue templates
ISSUE_TEMPLATE_DIRS = [
    ".github/ISSUE_TEMPLATE",
    ".github/issue_template",
]

# Dependabot
DEPENDABOT_CANDIDATES = [
    ".github/dependabot.yml",
    ".github/dependabot.yaml",
]

# Changelog / release drafter
CHANGELOG_CANDIDATES = [
    "CHANGELOG.md",
    ".github/release-drafter.yml",
    ".github/release-drafter.yaml",
]

# ADR — not present in tree yet, WARN only
ADR_CANDIDATES = [
    "docs/adr",
    "docs/ADR",
]

# Docs site scaffold — not present yet, WARN only
DOCS_SITE_CANDIDATES = [
    "mkdocs.yml",
    "mkdocs.yaml",
    "docs/index.md",
]

# Checkov config — must be at repo root for auto-discovery
CHECKOV_CANDIDATES = [
    ".checkov.yml",
    ".checkov.yaml",
]

# terraform-docs config
TERRAFORM_DOCS_CANDIDATES = [
    ".terraform-docs.yml",
    ".terraform-docs.yaml",
]

# Exact Terraform roots present in the repo
TF_ROOTS = [
    Path("infra/mgmt/backend"),
    Path("infra/mgmt/org"),
    Path("infra/live/shared"),
]

# infra/live roots that exist so far (only shared; dev/staging/prod are future)
LIVE_ROOTS_PRESENT = ["shared"]

# All modules present in infra/modules per the tree
MODULES_EXPECTED = [
    "ec2_instance",
    "iam_instance_profile",
    "iam_policy",
    "iam_role",
    "iam_role_oidc",
    "kms_key",
    "s3_secure_bucket",
    "security_group",
    "vpc_endpoint",
]

# Required files inside every module
MODULE_REQUIRED_FILES = [
    "main.tf",
    "variables.tf",
    "outputs.tf",
    "README.md",
    "versions.tf",
]

# Required OUs
REQUIRED_OUS = {"Security", "Infrastructure", "Workloads", "Sandbox"}

# Required tools on PATH
REQUIRED_TOOLS = [
    "git",
    "gh",
    "aws",
    "terraform",
    "tflint",
    "pre-commit",
    "checkov",
]

# Pre-commit hook tokens that must appear in .pre-commit-config.yaml
PRECOMMIT_REQUIRED_TOKENS = [
    "terraform_fmt",
    "tflint",
    "checkov",
    "gitleaks",
]

# Workflow scan tokens — at least one of these groups must match
SECURITY_SCAN_TOKEN_GROUPS = [
    ["checkov"],
    ["tflint"],
    ["gitleaks"],
]

# SCP name-pattern signals per attachment target
SCP_PATTERNS: Dict[str, List[str]] = {
    "root": ["leave"],
    "workloads": ["region"],
    "security": ["security"],
    "infrastructure": ["security"],
    "sandbox": ["security"],
}

# Paths to skip when discovering Terraform directories
TF_SKIP_PARTS = {
    ".terraform",
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    "test",
}


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class Result:
    name: str
    ok: bool
    detail: str
    severity: str = "fail"


@dataclass
class Suite:
    results: List[Result] = field(default_factory=list)

    def add(
        self,
        name: str,
        ok: bool,
        detail: str,
        severity: str = "fail",
    ) -> None:
        self.results.append(
            Result(name=name, ok=ok, detail=detail, severity=severity)
        )

    def ok_detail(self, ok: bool, pass_msg: str, fail_msg: str) -> str:
        return pass_msg if ok else fail_msg


# ---------------------------------------------------------------------------
# Shell helpers
# ---------------------------------------------------------------------------

def run(
    cmd: Sequence[str],
    cwd: Optional[Path] = None,
) -> Tuple[int, str, str]:
    proc = subprocess.run(
        list(cmd),
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def aws_json(
    profile: str,
    args: Sequence[str],
    region: Optional[str] = None,
) -> Tuple[bool, Dict]:
    cmd = ["aws", "--profile", profile]
    if region:
        cmd.extend(["--region", region])
    cmd.extend(list(args))
    cmd.extend(["--output", "json"])
    rc, out, err = run(cmd)
    if rc != 0:
        return False, {"error": err or out or "aws cli error (no output)"}
    try:
        return True, json.loads(out or "{}")
    except json.JSONDecodeError:
        return False, {"error": "invalid json", "raw": out[:200]}


# ---------------------------------------------------------------------------
# Repo helpers
# ---------------------------------------------------------------------------

def path_exists(repo_root: Path, candidates: Sequence[str]) -> bool:
    return any((repo_root / c).exists() for c in candidates)


def first_existing(
    repo_root: Path,
    candidates: Sequence[str],
) -> Optional[Path]:
    for c in candidates:
        p = repo_root / c
        if p.exists():
            return p
    return None


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def workflow_files(repo_root: Path) -> List[Path]:
    wf_dir = repo_root / ".github" / "workflows"
    if not wf_dir.exists():
        return []
    return sorted(wf_dir.glob("*.y*ml"))


def any_workflow_contains(
    repo_root: Path,
    tokens: Sequence[str],
) -> bool:
    for wf in workflow_files(repo_root):
        text = read_text(wf).lower()
        if all(t.lower() in text for t in tokens):
            return True
    return False


# ---------------------------------------------------------------------------
# E01 — Repo Bootstrap + SDLC
# ---------------------------------------------------------------------------

def check_tools(s: Suite) -> None:
    missing = [t for t in REQUIRED_TOOLS if shutil.which(t) is None]
    s.add(
        "local.tools.installed",
        not missing,
        "all required tools on PATH"
        if not missing else "missing: " + ", ".join(missing),
    )


def check_repo_structure(repo_root: Path, s: Suite) -> None:
    missing_dirs = [
        d for d in REQUIRED_REPO_DIRS if not (repo_root / d).is_dir()
    ]
    s.add(
        "e01.repo.directories",
        not missing_dirs,
        "required directories present"
        if not missing_dirs else "missing: " + ", ".join(missing_dirs),
    )

    missing_files = [
        f for f in REQUIRED_REPO_FILES if not (repo_root / f).exists()
    ]
    s.add(
        "e01.repo.core_files",
        not missing_files,
        "LICENSE, SECURITY.md, CONTRIBUTING.md, README.md present"
        if not missing_files else "missing: " + ", ".join(missing_files),
    )

    codeowners = first_existing(repo_root, CODEOWNERS_CANDIDATES)
    if codeowners:
        text = read_text(codeowners)
        infra_ok = "/infra" in text
        s.add(
            "e01.repo.codeowners",
            infra_ok,
            "CODEOWNERS present and includes /infra rule"
            if infra_ok else "CODEOWNERS found but /infra rule missing",
        )
    else:
        s.add("e01.repo.codeowners", False, "CODEOWNERS not found")


def check_github_standards(repo_root: Path, s: Suite) -> None:
    s.add(
        "e01.github.issue_templates",
        path_exists(repo_root, ISSUE_TEMPLATE_DIRS),
        ".github/ISSUE_TEMPLATE directory present"
        if path_exists(repo_root, ISSUE_TEMPLATE_DIRS)
        else ".github/ISSUE_TEMPLATE not found",
    )

    s.add(
        "e01.github.pr_template",
        path_exists(repo_root, PR_TEMPLATE_CANDIDATES),
        "PR template present"
        if path_exists(repo_root, PR_TEMPLATE_CANDIDATES)
        else "PR template not found",
    )

    s.add(
        "e01.github.dependabot",
        path_exists(repo_root, DEPENDABOT_CANDIDATES),
        "Dependabot config present"
        if path_exists(repo_root, DEPENDABOT_CANDIDATES)
        else "Dependabot config not found",
    )

    s.add(
        "e01.github.changelog_or_release_drafter",
        path_exists(repo_root, CHANGELOG_CANDIDATES),
        "changelog/release drafter present"
        if path_exists(repo_root, CHANGELOG_CANDIDATES)
        else "changelog automation not found",
        severity="warn",
    )

    s.add(
        "e01.docs.adr_log",
        path_exists(repo_root, ADR_CANDIDATES),
        "ADR directory present"
        if path_exists(repo_root, ADR_CANDIDATES)
        else "docs/adr not found (not yet created)",
        severity="warn",
    )

    s.add(
        "e01.docs.site_scaffold",
        path_exists(repo_root, DOCS_SITE_CANDIDATES),
        "docs site scaffold present"
        if path_exists(repo_root, DOCS_SITE_CANDIDATES)
        else "docs site scaffold not found (not yet created)",
        severity="warn",
    )

    wf_ok = bool(workflow_files(repo_root))
    s.add(
        "e01.github.workflows.exist",
        wf_ok,
        "workflow files found in .github/workflows"
        if wf_ok else ".github/workflows missing or empty",
    )

    scan_ok = any(
        any_workflow_contains(repo_root, grp)
        for grp in SECURITY_SCAN_TOKEN_GROUPS
    )
    s.add(
        "e01.github.security_scans",
        scan_ok,
        "security scanning signals found in workflows"
        if scan_ok else "no IaC/security scan tokens found in workflows",
    )

    release_ok = (
        any_workflow_contains(repo_root, ["semver"])
        or any_workflow_contains(repo_root, ["release"])
        or any_workflow_contains(repo_root, ["tag"])
    )
    s.add(
        "e01.github.semver_signal",
        release_ok,
        "semver/release signal found in workflows"
        if release_ok else "no semver/release signal found",
        severity="warn",
    )


def check_pre_commit(repo_root: Path, s: Suite) -> None:
    path = repo_root / ".pre-commit-config.yaml"
    if not path.exists():
        s.add("e01.precommit.config", False, ".pre-commit-config.yaml not found")
        return

    text = read_text(path).lower()
    missing = [t for t in PRECOMMIT_REQUIRED_TOKENS if t not in text]
    ok = not missing
    s.add(
        "e01.precommit.hooks",
        ok,
        "pre-commit includes terraform_fmt, tflint, checkov, gitleaks"
        if ok else "missing hook tokens: " + ", ".join(missing),
    )


# ---------------------------------------------------------------------------
# E02 — Terraform Foundations + State
# ---------------------------------------------------------------------------

def check_terraform_layout(repo_root: Path, s: Suite) -> None:
    # infra/live/shared is the only live root so far
    for live_dir in LIVE_ROOTS_PRESENT:
        live_path = repo_root / "infra" / "live" / live_dir
        s.add(
            "e02.layout.live." + live_dir,
            live_path.exists(),
            "infra/live/" + live_dir + " present"
            if live_path.exists()
            else "infra/live/" + live_dir + " missing",
        )

    modules_root = repo_root / "infra" / "modules"
    s.add(
        "e02.layout.modules_root",
        modules_root.is_dir(),
        "infra/modules present"
        if modules_root.is_dir() else "infra/modules missing",
    )

    for module_name in MODULES_EXPECTED:
        module_path = modules_root / module_name
        missing_files = [
            f for f in MODULE_REQUIRED_FILES
            if not (module_path / f).exists()
        ]
        s.add(
            "e02.module." + module_name,
            not missing_files,
            "module interface complete (main/variables/outputs/README/versions)"
            if not missing_files
            else "missing: " + ", ".join(missing_files),
        )

    s.add(
        "e02.hygiene.tflint_config",
        (repo_root / ".tflint.hcl").exists(),
        ".tflint.hcl present"
        if (repo_root / ".tflint.hcl").exists()
        else ".tflint.hcl not found",
    )

    s.add(
        "e02.hygiene.checkov_config",
        path_exists(repo_root, CHECKOV_CANDIDATES),
        ".checkov.yml present"
        if path_exists(repo_root, CHECKOV_CANDIDATES)
        else ".checkov.yml not found",
    )

    s.add(
        "e02.hygiene.terraform_docs_config",
        path_exists(repo_root, TERRAFORM_DOCS_CANDIDATES),
        "terraform-docs config present"
        if path_exists(repo_root, TERRAFORM_DOCS_CANDIDATES)
        else "terraform-docs config not found",
        severity="warn",
    )

    # Verify each known Terraform root exists
    for tf_root in TF_ROOTS:
        full = repo_root / tf_root
        s.add(
            "e02.tf_root." + str(tf_root).replace("/", "."),
            full.is_dir(),
            str(tf_root) + " present"
            if full.is_dir() else str(tf_root) + " missing",
        )


def check_local_validation_commands(repo_root: Path, s: Suite) -> None:
    infra_root = repo_root / "infra"

    # terraform fmt -check across infra/
    rc, _, err = run(
        ["terraform", "fmt", "-check", "-recursive"],
        cwd=infra_root,
    )
    s.add(
        "e02.local.terraform_fmt",
        rc == 0,
        "terraform fmt -check passed"
        if rc == 0 else (err or "terraform fmt check failed"),
    )

    # terraform init + validate for each known root
    for tf_root in TF_ROOTS:
        full = repo_root / tf_root
        if not full.is_dir():
            s.add(
                "e02.local.terraform_validate." + str(tf_root).replace("/", "."),
                False,
                str(tf_root) + " directory not found",
            )
            continue

        rc, _, err = run(
            ["terraform", "init", "-backend=false", "-input=false", "-no-color"],
            cwd=full,
        )
        if rc != 0:
            s.add(
                "e02.local.terraform_validate."
                + str(tf_root).replace("/", "."),
                False,
                "terraform init failed: " + (err or "").splitlines()[0]
                if err else "terraform init failed",
            )
            continue

        rc, _, err = run(
            ["terraform", "validate", "-no-color"],
            cwd=full,
        )
        s.add(
            "e02.local.terraform_validate." + str(tf_root).replace("/", "."),
            rc == 0,
            "terraform validate passed"
            if rc == 0 else (err or "terraform validate failed").splitlines()[0],
        )

    # pre-commit run --all-files (warn only — can be slow/noisy in CI)
    rc, _, err = run(["pre-commit", "run", "--all-files"], cwd=repo_root)
    s.add(
        "e02.local.pre_commit_all_files",
        rc == 0,
        "pre-commit run --all-files passed"
        if rc == 0 else (err or "pre-commit failed"),
        severity="warn",
    )


# ---------------------------------------------------------------------------
# E03 — AWS Org + Control Tower + Governance
# ---------------------------------------------------------------------------

def check_aws_identity(
    profile: str,
    expected_account: str,
    s: Suite,
) -> None:
    ok, data = aws_json(profile, ["sts", "get-caller-identity"])
    if not ok:
        s.add("e03.aws.identity", False, data["error"])
        return

    account_ok = data.get("Account") == expected_account
    s.add(
        "e03.aws.identity",
        account_ok,
        "caller identity confirmed: account " + expected_account
        if account_ok else
        "expected " + expected_account + ", got " + str(data.get("Account")),
    )


def check_organization(
    profile: str,
    s: Suite,
) -> Optional[str]:
    ok, data = aws_json(profile, ["organizations", "describe-organization"])
    if not ok:
        s.add("e03.org.describe", False, data["error"])
        return None

    org = data.get("Organization", {})
    feature_ok = org.get("FeatureSet") == "ALL"
    s.add(
        "e03.org.feature_set",
        feature_ok,
        "organization FeatureSet=ALL"
        if feature_ok else "FeatureSet=" + str(org.get("FeatureSet")),
    )

    ok, data = aws_json(
        profile,
        ["organizations", "list-aws-service-access-for-organization"],
    )
    if not ok:
        s.add("e03.org.service_access", False, data["error"])
    else:
        principals = {
            item.get("ServicePrincipal", "")
            for item in data.get("EnabledServicePrincipals", [])
        }
        needed = "member.org.stacksets.cloudformation.amazonaws.com"
        s.add(
            "e03.org.service_access.controltower_stacksets",
            needed in principals,
            "Control Tower StackSets service principal enabled"
            if needed in principals else "missing: " + needed,
        )

    ok, data = aws_json(profile, ["organizations", "list-roots"])
    if not ok:
        s.add("e03.org.roots", False, data["error"])
        return None

    roots = data.get("Roots", [])
    root_id = roots[0].get("Id") if roots else None
    s.add(
        "e03.org.roots",
        bool(root_id),
        "organization root found: " + str(root_id)
        if root_id else "no organization root found",
    )
    return root_id


def check_ous(
    profile: str,
    root_id: str,
    s: Suite,
) -> Dict[str, str]:
    ok, data = aws_json(
        profile,
        [
            "organizations",
            "list-organizational-units-for-parent",
            "--parent-id",
            root_id,
        ],
    )
    if not ok:
        s.add("e03.org.ous", False, data["error"])
        return {}

    ou_map = {
        item.get("Name", ""): item.get("Id", "")
        for item in data.get("OrganizationalUnits", [])
    }
    missing = sorted(REQUIRED_OUS.difference(set(ou_map.keys())))
    s.add(
        "e03.org.ous",
        not missing,
        "all required OUs present: " + ", ".join(sorted(ou_map.keys()))
        if not missing else "missing OUs: " + ", ".join(missing),
    )
    return ou_map


def check_state_backend(
    profile: str,
    state_bucket: str,
    lock_table: str,
    primary_region: str,
    replica_region: str,
    s: Suite,
) -> None:
    # Encryption
    ok, data = aws_json(
        profile,
        ["s3api", "get-bucket-encryption", "--bucket", state_bucket],
        region=primary_region,
    )
    if not ok:
        s.add("e02.aws.state_bucket.encryption", False, data["error"])
    else:
        rules = (
            data.get("ServerSideEncryptionConfiguration", {}).get("Rules", [])
        )
        kms_ok = any(
            rule.get("ApplyServerSideEncryptionByDefault", {}).get(
                "SSEAlgorithm"
            ) == "aws:kms"
            for rule in rules
        )
        s.add(
            "e02.aws.state_bucket.encryption",
            kms_ok,
            "state bucket SSE-KMS encryption confirmed"
            if kms_ok else "state bucket not using SSE-KMS",
        )

    # Versioning
    ok, data = aws_json(
        profile,
        ["s3api", "get-bucket-versioning", "--bucket", state_bucket],
        region=primary_region,
    )
    if not ok:
        s.add("e02.aws.state_bucket.versioning", False, data["error"])
    else:
        s.add(
            "e02.aws.state_bucket.versioning",
            data.get("Status") == "Enabled",
            "state bucket versioning enabled"
            if data.get("Status") == "Enabled"
            else "state bucket versioning not enabled",
        )

    # Public access block
    ok, data = aws_json(
        profile,
        ["s3api", "get-public-access-block", "--bucket", state_bucket],
        region=primary_region,
    )
    if not ok:
        s.add("e02.aws.state_bucket.public_access_block", False, data["error"])
    else:
        block = data.get("PublicAccessBlockConfiguration", {})
        block_ok = all(bool(block.get(k)) for k in block)
        s.add(
            "e02.aws.state_bucket.public_access_block",
            block_ok,
            "all public access block settings enabled"
            if block_ok else "public access block not fully enabled: " + str(block),
        )

    # Cross-region replication (primary → replica)
    ok, data = aws_json(
        profile,
        ["s3api", "get-bucket-replication", "--bucket", state_bucket],
        region=primary_region,
    )
    if ok:
        rules = (
            data.get("ReplicationConfiguration", {}).get("Rules", [])
        )
        replica_ok = any(
            replica_region in json.dumps(rule)
            for rule in rules
        )
        s.add(
            "e02.aws.state_bucket.replication",
            replica_ok,
            "cross-region replication to " + replica_region + " confirmed"
            if replica_ok else
            "replication configured but " + replica_region + " not found in rules",
        )
    else:
        s.add(
            "e02.aws.state_bucket.replication",
            False,
            "replication not configured: " + data["error"],
            severity="warn",
        )

    # DynamoDB lock table
    ok, data = aws_json(
        profile,
        ["dynamodb", "describe-table", "--table-name", lock_table],
        region=primary_region,
    )
    if not ok:
        s.add("e02.aws.lock_table.exists", False, data["error"])
        return

    table = data.get("Table", {})
    s.add(
        "e02.aws.lock_table.exists",
        table.get("TableName") == lock_table,
        "DynamoDB lock table exists"
        if table.get("TableName") == lock_table
        else "lock table name mismatch",
    )

    sse = table.get("SSEDescription", {}).get("Status")
    s.add(
        "e02.aws.lock_table.sse",
        sse in {"ENABLED", "UPDATING"},
        "DynamoDB lock table SSE enabled"
        if sse in {"ENABLED", "UPDATING"}
        else "DynamoDB lock table SSE not enabled (status: " + str(sse) + ")",
    )


def check_control_tower(
    profile: str,
    primary_region: str,
    s: Suite,
) -> None:
    ok, data = aws_json(
        profile,
        ["controltower", "list-landing-zones"],
        region=primary_region,
    )
    if not ok:
        s.add(
            "e03.control_tower.landing_zone",
            False,
            data["error"],
            severity="warn",
        )
        return

    summaries = data.get("landingZones", []) or data.get("LandingZones", [])
    s.add(
        "e03.control_tower.landing_zone",
        bool(summaries),
        "Control Tower landing zone discovered"
        if summaries else "no landing zone found",
    )


def check_cloudtrail(
    profile: str,
    primary_region: str,
    s: Suite,
) -> None:
    ok, data = aws_json(
        profile,
        ["cloudtrail", "describe-trails", "--include-shadow-trails"],
        region=primary_region,
    )
    if not ok:
        s.add("e03.cloudtrail.describe", False, data["error"])
        return

    trails = data.get("trailList", [])
    org_trails = [t for t in trails if t.get("IsOrganizationTrail")]

    if not org_trails:
        s.add("e03.cloudtrail.org_trail", False, "no organization trail found")
        return

    trail = org_trails[0]
    trail_name = trail.get("Name", "<​unnamed>")

    s.add(
        "e03.cloudtrail.org_trail",
        True,
        "organization trail found: " + trail_name,
    )

    s.add(
        "e03.cloudtrail.multi_region",
        bool(trail.get("IsMultiRegionTrail")),
        "org trail is multi-region"
        if trail.get("IsMultiRegionTrail")
        else "org trail is NOT multi-region",
    )

    s.add(
        "e03.cloudtrail.kms",
        bool(trail.get("KmsKeyId")),
        "CloudTrail KMS CMK configured"
        if trail.get("KmsKeyId")
        else "CloudTrail KMS key missing",
    )

    s.add(
        "e03.cloudtrail.log_file_validation",
        bool(trail.get("LogFileValidationEnabled")),
        "log file validation enabled"
        if trail.get("LogFileValidationEnabled")
        else "log file validation not enabled",
    )

    ok, status = aws_json(
        profile,
        ["cloudtrail", "get-trail-status", "--name", trail_name],
        region=primary_region,
    )
    if not ok:
        s.add("e03.cloudtrail.logging", False, status["error"])
        return

    s.add(
        "e03.cloudtrail.logging",
        bool(status.get("IsLogging")),
        "CloudTrail is actively logging"
        if status.get("IsLogging")
        else "CloudTrail is NOT logging",
    )

    # CloudWatch Logs integration (known exception: may be in S3-only mode)
    cw_arn = trail.get("CloudWatchLogsLogGroupArn")
    s.add(
        "e03.cloudtrail.cloudwatch_logs",
        bool(cw_arn),
        "CloudTrail CloudWatch Logs integration present"
        if cw_arn else
        "CloudTrail running in S3-only mode (known exception per MEMORY.md)",
        severity="warn",
    )


def check_config_aggregator(
    profile: str,
    primary_region: str,
    s: Suite,
) -> None:
    ok, data = aws_json(
        profile,
        ["configservice", "describe-configuration-aggregators"],
        region=primary_region,
    )
    if not ok:
        s.add("e03.config.aggregator", False, data["error"])
        return

    aggs = data.get("ConfigurationAggregators", [])
    s.add(
        "e03.config.aggregator",
        bool(aggs),
        "Config aggregator present: " + ", ".join(
            a.get("ConfigurationAggregatorName", "") for a in aggs
        )
        if aggs else "no Config aggregator found",
    )

    if aggs:
        agg = aggs[0]
        org_src = agg.get("OrganizationAggregationSource")
        s.add(
            "e03.config.aggregator.org_source",
            bool(org_src),
            "aggregator uses organization source"
            if org_src else "aggregator does not use organization source",
        )


def check_guardduty(
    profile: str,
    admin_account: str,
    regions: Sequence[str],
    s: Suite,
) -> None:
    ok, data = aws_json(
        profile,
        ["guardduty", "list-organization-admin-accounts"],
        region=regions[0],
    )
    if not ok:
        s.add("e03.guardduty.admin_account", False, data["error"])
    else:
        admins = {
            item.get("AdminAccountId", "")
            for item in data.get("AdminAccounts", [])
        }
        s.add(
            "e03.guardduty.admin_account",
            admin_account in admins,
            "GuardDuty delegated admin confirmed: " + admin_account
            if admin_account in admins
            else "expected " + admin_account + " not in admin accounts: "
            + str(admins),
        )

    for region in regions:
        ok, data = aws_json(
            profile,
            ["guardduty", "list-detectors"],
            region=region,
        )
        if not ok:
            s.add(
                "e03.guardduty.detector." + region,
                False,
                data["error"],
            )
            continue

        ids = data.get("DetectorIds", [])
        if not ids:
            s.add(
                "e03.guardduty.detector." + region,
                False,
                "no GuardDuty detector in " + region,
            )
            continue

        ok, detector = aws_json(
            profile,
            ["guardduty", "get-detector", "--detector-id", ids[0]],
            region=region,
        )
        if not ok:
            s.add(
                "e03.guardduty.detector." + region,
                False,
                detector["error"],
            )
            continue

        enabled = detector.get("Status") == "ENABLED"
        freq_ok = (
            detector.get("FindingPublishingFrequency") == "FIFTEEN_MINUTES"
        )
        s.add(
            "e03.guardduty.detector." + region,
            enabled,
            "detector ENABLED in " + region
            if enabled else "detector not ENABLED in " + region,
        )
        s.add(
            "e03.guardduty.finding_frequency." + region,
            freq_ok,
            "finding frequency FIFTEEN_MINUTES in " + region
            if freq_ok else
            "finding frequency is "
            + str(detector.get("FindingPublishingFrequency"))
            + " in " + region,
        )


def check_security_hub(
    profile: str,
    admin_account: str,
    primary_region: str,
    s: Suite,
) -> None:
    ok, data = aws_json(
        profile,
        ["securityhub", "list-organization-admin-accounts"],
        region=primary_region,
    )
    if not ok:
        s.add("e03.securityhub.admin_account", False, data["error"])
    else:
        admins = {
            item.get("AccountId", "")
            for item in data.get("AdminAccounts", [])
        }
        s.add(
            "e03.securityhub.admin_account",
            admin_account in admins,
            "Security Hub delegated admin confirmed: " + admin_account
            if admin_account in admins
            else "expected " + admin_account + " not found in admin accounts",
        )

    ok, data = aws_json(
        profile,
        ["securityhub", "get-enabled-standards"],
        region=primary_region,
    )
    if not ok:
        s.add("e03.securityhub.standards", False, data["error"])
    else:
        subs = data.get("StandardsSubscriptions", [])
        names = [
            sub.get("StandardsArn", "").split("/")[-2]
            for sub in subs
        ]
        s.add(
            "e03.securityhub.standards",
            bool(subs),
            "standards enabled: " + ", ".join(names)
            if subs else "no Security Hub standards enabled",
        )

    ok, data = aws_json(
        profile,
        ["securityhub", "list-finding-aggregators"],
        region=primary_region,
    )
    if not ok:
        s.add("e03.securityhub.finding_aggregator", False, data["error"])
    else:
        aggs = data.get("FindingAggregators", [])
        s.add(
            "e03.securityhub.finding_aggregator",
            bool(aggs),
            "finding aggregator present"
            if aggs else "no finding aggregator found",
        )


def check_budgets_and_anomalies(
    profile: str,
    mgmt_account: str,
    primary_region: str,
    s: Suite,
) -> None:
    ok, data = aws_json(
        profile,
        ["budgets", "describe-budgets", "--account-id", mgmt_account],
        region=primary_region,
    )
    if not ok:
        s.add("e03.finops.budgets", False, data["error"])
    else:
        budgets = data.get("Budgets", [])
        names = [b.get("BudgetName", "") for b in budgets]
        s.add(
            "e03.finops.budgets",
            bool(budgets),
            "budget(s) configured: " + ", ".join(names)
            if budgets else "no budgets found",
        )

    ok, data = aws_json(
        profile,
        ["ce", "get-anomaly-monitors"],
        region=primary_region,
    )
    if not ok:
        s.add("e03.finops.anomaly_monitors", False, data["error"])
    else:
        monitors = data.get("AnomalyMonitors", [])
        s.add(
            "e03.finops.anomaly_monitors",
            bool(monitors),
            "anomaly monitor(s) configured"
            if monitors else "no cost anomaly monitors found",
        )

    ok, data = aws_json(
        profile,
        ["ce", "get-anomaly-subscriptions"],
        region=primary_region,
    )
    if not ok:
        s.add("e03.finops.anomaly_subscriptions", False, data["error"])
    else:
        subs = data.get("AnomalySubscriptions", [])
        s.add(
            "e03.finops.anomaly_subscriptions",
            bool(subs),
            "anomaly subscription(s) configured"
            if subs else "no cost anomaly subscriptions found",
        )


def check_scps(
    profile: str,
    root_id: str,
    ou_map: Dict[str, str],
    s: Suite,
) -> None:
    ok, data = aws_json(
        profile,
        ["organizations", "list-policies", "--filter", "SERVICE_CONTROL_POLICY"],
    )
    if not ok:
        s.add("e03.scp.policies_exist", False, data["error"])
        return

    policies = data.get("Policies", [])
    s.add(
        "e03.scp.policies_exist",
        bool(policies),
        str(len(policies)) + " SCP(s) found"
        if policies else "no SCPs found",
    )

    policy_by_id = {
        item.get("Id", ""): item.get("Name", "")
        for item in policies
    }

    # Targets: root + all four OUs
    targets = {
        "root": root_id,
        "workloads": ou_map.get("Workloads", ""),
        "security": ou_map.get("Security", ""),
        "infrastructure": ou_map.get("Infrastructure", ""),
        "sandbox": ou_map.get("Sandbox", ""),
    }

    for label, target_id in targets.items():
        if not target_id:
            s.add(
                "e03.scp.attachments." + label,
                False,
                "target id not found for " + label,
            )
            continue

        ok, data = aws_json(
            profile,
            [
                "organizations",
                "list-policies-for-target",
                "--target-id",
                target_id,
                "--filter",
                "SERVICE_CONTROL_POLICY",
            ],
        )
        if not ok:
            s.add("e03.scp.attachments." + label, False, data["error"])
            continue

        attached_names = [
            policy_by_id.get(item.get("Id", ""), "")
            for item in data.get("Policies", [])
        ]
        name_blob = " ".join(n.lower() for n in attached_names)
        needed = SCP_PATTERNS.get(label, [])
        matched = all(token in name_blob for token in needed)
        s.add(
            "e03.scp.attachments." + label,
            matched,
            "SCP attachment signals matched for " + label
            + " (" + ", ".join(attached_names) + ")"
            if matched else
            "SCP pattern mismatch for " + label
            + "; attached: " + (", ".join(attached_names) or "none"),
            severity="warn",
        )


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def print_summary(results: Sequence[Result]) -> int:
    col_width = max(len(r.name) for r in results) + 2
    failures = 0
    warnings = 0

    for r in results:
        if r.ok:
            status = "PASS"
        elif r.severity == "warn":
            status = "WARN"
            warnings += 1
        else:
            status = "FAIL"
            failures += 1
        print(f"[{status:<4}] {r.name:<{col_width}} {r.detail}")

    print("")
    print("─" * 60)
    print(f"  total   : {len(results)}")
    print(f"  pass    : {len(results) - failures - warnings}")
    print(f"  warn    : {warnings}")
    print(f"  fail    : {failures}")
    print("─" * 60)

    return 1 if failures else 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate infra-lab foundations: E01 (repo/SDLC), "
            "E02 (Terraform), E03 (AWS governance)."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Path to repository root",
    )
    parser.add_argument("--profile", default=DEFAULT_PROFILE)
    parser.add_argument("--primary-region", default=DEFAULT_PRIMARY_REGION)
    parser.add_argument("--replica-region", default=DEFAULT_REPLICA_REGION)
    parser.add_argument("--mgmt-account", default=DEFAULT_MGMT_ACCOUNT)
    parser.add_argument(
        "--guardduty-admin-account",
        default=DEFAULT_GD_ADMIN_ACCOUNT,
    )
    parser.add_argument(
        "--securityhub-admin-account",
        default=DEFAULT_SH_ADMIN_ACCOUNT,
    )
    parser.add_argument("--state-bucket", default=DEFAULT_STATE_BUCKET)
    parser.add_argument("--lock-table", default=DEFAULT_LOCK_TABLE)
    parser.add_argument(
        "--skip-local",
        action="store_true",
        help="Skip repo/local tooling and Terraform checks",
    )
    parser.add_argument(
        "--skip-aws",
        action="store_true",
        help="Skip all live AWS API checks",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).expanduser().resolve()

    if not repo_root.exists():
        print(
            "error: repo root does not exist: " + str(repo_root),
            file=sys.stderr,
        )
        return 2

    s = Suite()

    if not args.skip_local:
        check_tools(s)
        check_repo_structure(repo_root, s)
        check_github_standards(repo_root, s)
        check_pre_commit(repo_root, s)
        check_terraform_layout(repo_root, s)
        check_local_validation_commands(repo_root, s)

    if not args.skip_aws:
        check_aws_identity(args.mgmt_account, args.mgmt_account, s)
        root_id = check_organization(args.profile, s)
        ou_map: Dict[str, str] = {}
        if root_id:
            ou_map = check_ous(args.profile, root_id, s)

        check_state_backend(
            args.profile,
            args.state_bucket,
            args.lock_table,
            args.primary_region,
            args.replica_region,
            s,
        )
        check_control_tower(args.profile, args.primary_region, s)
        check_cloudtrail(args.profile, args.primary_region, s)
        check_config_aggregator(args.profile, args.primary_region, s)
        check_guardduty(
            args.profile,
            args.guardduty_admin_account,
            [args.primary_region, args.replica_region],
            s,
        )
        check_security_hub(
            args.profile,
            args.securityhub_admin_account,
            args.primary_region,
            s,
        )
        check_budgets_and_anomalies(
            args.profile,
            args.mgmt_account,
            args.primary_region,
            s,
        )
        if root_id:
            check_scps(args.profile, root_id, ou_map, s)

    return print_summary(s.results)


if __name__ == "__main__":
    sys.exit(main())
