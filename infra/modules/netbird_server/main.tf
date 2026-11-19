# NetBird Self-Hosted Server on ECS Fargate
# ADR-037: Self-Hosted NetBird Server in a Dedicated Account, Torn Down When Idle
#
# Runs the upstream single-host topology (Traefik in front of the combined
# netbird-server plus the dashboard) as one Fargate task, with one EFS
# filesystem for state. Containers share the task's network namespace, so
# Traefik reaches the server and the dashboard over localhost, the same way
# it reaches them over the compose bridge network upstream.
#
# Containers:
#   config-init     renders config.yaml and Traefik's dynamic config onto a
#                   task-local volume from Terraform-rendered templates, then
#                   exits. Uses the Traefik image (it ships /bin/sh), so no
#                   extra image to pin.
#   netbird-server  management, signal, relay (WebSocket on the HTTPS path)
#                   and, unless stun_servers is set, embedded STUN on UDP.
#   dashboard       web UI on :80.
#   traefik         the only TCP entrypoint, target of the NLB HTTPS target
#                   group. Routes gRPC as h2c, everything else as HTTP/1.1.
#
# Scope boundary (same as mempalace_server): this module owns compute and
# storage for the app. VPC, NLB, listeners, target groups, ACM certificate,
# Route53 records, KMS key, ECS cluster, and the Secrets Manager secrets
# AND their values belong to the caller. That keeps the module portable.
#
# Secrets never appear in Terraform state or in any file on EFS:
# NB_AUTH_SECRET, NB_STORE_ENCRYPTION_KEY and
# NB_IDP_SESSION_COOKIE_ENCRYPTION_KEY are injected from Secrets Manager by
# ECS. The only secret ever written to a file is the optional initial owner
# password, and only to task-local ephemeral storage (encrypted by Fargate,
# gone when the task stops).

locals {
  name_prefix = var.name
  common_tags = merge(var.tags, {
    "ManagedBy" = "terraform"
    "Project"   = var.project
    "App"       = "netbird-server"
  })

  embedded_stun = length(var.stun_servers) == 0
  traefik_tls   = var.tls_mode == "traefik"
  seed_owner    = var.owner_secret_arn != null

  netbird_config = templatefile("${path.module}/templates/config.yaml.tftpl", {
    domain                    = var.domain
    server_port               = var.server_port
    stun_port                 = var.stun_port
    stun_servers              = var.stun_servers
    metrics_port              = var.metrics_port
    health_port               = var.health_port
    log_level                 = var.log_level
    disable_anonymous_metrics = var.disable_anonymous_metrics
  })

  traefik_dynamic = templatefile("${path.module}/templates/traefik-dynamic.yaml.tftpl", {
    domain      = var.domain
    server_port = var.server_port
    tls_mode    = var.tls_mode
  })

  # Same flags as the upstream option-0 compose file, minus the Docker
  # provider and the :80 redirect entrypoint (the NLB only forwards 443),
  # plus the file provider. Zero timeouts are required for long-lived
  # gRPC streams and relay WebSockets.
  traefik_command = concat(
    [
      "--log.level=INFO",
      "--accesslog=true",
      "--providers.file.filename=/config/traefik-dynamic.yaml",
      "--entrypoints.netbird.address=:${var.https_port}",
      "--entrypoints.netbird.http.aliasHeadersStrategy=delete",
      "--entrypoints.netbird.transport.respondingTimeouts.readTimeout=0",
      "--entrypoints.netbird.transport.respondingTimeouts.writeTimeout=0",
      "--entrypoints.netbird.transport.respondingTimeouts.idleTimeout=0",
      "--serverstransport.forwardingtimeouts.responseheadertimeout=0s",
      "--serverstransport.forwardingtimeouts.idleconntimeout=0s",
    ],
    local.traefik_tls ? [
      "--entrypoints.netbird.allowACMEByPass=true",
      "--certificatesresolvers.letsencrypt.acme.email=${coalesce(var.acme_email, "unset")}",
      "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json",
      "--certificatesresolvers.letsencrypt.acme.tlschallenge=true",
    ] : [],
    length(var.proxy_protocol_trusted_cidrs) > 0 ? [
      "--entrypoints.netbird.proxyProtocol.trustedIPs=${join(",", var.proxy_protocol_trusted_cidrs)}",
    ] : [],
  )

  # Writes both rendered files onto the shared task-local volume. The owner
  # block is appended under `auth:` (the template keeps auth last) only when
  # an owner secret is wired in. Hex passwords need no YAML escaping.
  init_script = <<-EOT
    set -eu
    printf '%s\n' "$NB_CONFIG_YAML" > /config/config.yaml
    if [ -n "$${NB_OWNER_EMAIL:-}" ]; then
      printf '    owner:\n      email: "%s"\n      password: "%s"\n' "$NB_OWNER_EMAIL" "$NB_OWNER_PASSWORD" >> /config/config.yaml
    fi
    printf '%s\n' "$TRAEFIK_DYNAMIC_YAML" > /config/traefik-dynamic.yaml
    echo "netbird config rendered"
  EOT

  # From the upstream installer's render_dashboard_env, embedded IdP.
  dashboard_environment = [
    { name = "NETBIRD_MGMT_API_ENDPOINT", value = "https://${var.domain}" },
    { name = "NETBIRD_MGMT_GRPC_API_ENDPOINT", value = "https://${var.domain}" },
    { name = "AUTH_AUDIENCE", value = "netbird-dashboard" },
    { name = "AUTH_CLIENT_ID", value = "netbird-dashboard" },
    { name = "AUTH_CLIENT_SECRET", value = "" },
    { name = "AUTH_AUTHORITY", value = "https://${var.domain}/oauth2" },
    { name = "USE_AUTH0", value = "false" },
    { name = "AUTH_SUPPORTED_SCOPES", value = "openid profile email groups" },
    { name = "AUTH_REDIRECT_URI", value = "/nb-auth" },
    { name = "AUTH_SILENT_REDIRECT_URI", value = "/nb-silent-auth" },
    { name = "NGINX_SSL_PORT", value = "443" },
    { name = "LETSENCRYPT_DOMAIN", value = "none" },
  ]

  secret_arns = compact([
    var.auth_secret_arn,
    var.store_encryption_key_secret_arn,
    var.session_cookie_key_secret_arn,
    var.owner_secret_arn,
  ])

  log_options = {
    "awslogs-group"  = aws_cloudwatch_log_group.this.name
    "awslogs-region" = var.aws_region
  }
}

###############################################################################
# EFS: server state (/var/lib/netbird) and, in tls_mode "traefik", the ACME
# account and certificate so a bring-up reuses the certificate instead of
# re-issuing (Let's Encrypt rate limits).
###############################################################################

resource "aws_efs_file_system" "this" {
  # checkov:skip=CKV_AWS_184: "kms_key_arn null falls back to the aws/elasticfilesystem default key; caller controls via var.kms_key_arn"
  creation_token   = "${local.name_prefix}-data"
  encrypted        = true
  kms_key_id       = var.kms_key_arn
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-data"
  })
}

resource "aws_efs_mount_target" "this" {
  # Index-keyed for the same reason as mempalace_server: subnet IDs are
  # unknown at plan time on a fresh apply.
  for_each = { for idx, s in var.subnet_ids : idx => s }

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# All upstream images run as root, so the access points do too. The access
# point still pins every client to its own subdirectory.
resource "aws_efs_access_point" "data" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 0
    gid = 0
  }

  root_directory {
    path = "/netbird-data"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0700"
    }
  }

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-data"
  })
}

resource "aws_efs_access_point" "acme" {
  count = local.traefik_tls ? 1 : 0

  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 0
    gid = 0
  }

  root_directory {
    path = "/traefik-acme"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0700"
    }
  }

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-acme"
  })
}

###############################################################################
# Security Groups
###############################################################################

# TCP only from the caller's front door (the NLB SG). UDP STUN from
# stun_ingress_cidr_blocks, because NLB UDP target groups preserve the
# client source IP and STUN is meant to be publicly reachable.
module "task_sg" {
  source = "../security_group"

  name        = "${local.name_prefix}-task"
  description = "NetBird ECS task, TCP from the load balancer only, UDP STUN"
  vpc_id      = var.vpc_id

  ingress = concat(
    [
      {
        description     = "Traefik HTTPS entrypoint from load balancer"
        from_port       = var.https_port
        to_port         = var.https_port
        protocol        = "tcp"
        security_groups = var.ingress_security_group_ids
      },
      {
        description     = "NetBird server health check from load balancer"
        from_port       = var.health_port
        to_port         = var.health_port
        protocol        = "tcp"
        security_groups = var.ingress_security_group_ids
      },
    ],
    local.embedded_stun ? [
      {
        description = "Embedded STUN"
        from_port   = var.stun_port
        to_port     = var.stun_port
        protocol    = "udp"
        cidr_blocks = var.stun_ingress_cidr_blocks
      }
    ] : [],
  )

  egress = [
    {
      description = "All outbound (image pulls, EFS, Secrets Manager, CloudWatch Logs, Lets Encrypt, GeoLite updates)"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = local.common_tags
}

resource "aws_security_group" "efs" {
  name        = "${local.name_prefix}-efs"
  description = "NetBird EFS mount targets, NFS from the task only"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-efs"
  })
}

resource "aws_security_group_rule" "efs_from_task" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  description              = "NFS from NetBird ECS task"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = module.task_sg.id
}

###############################################################################
# IAM
###############################################################################

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: pulls images, writes logs, reads exactly the secrets
# passed in.
resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-ecs-execution"
  })
}

resource "aws_iam_role_policy_attachment" "execution_base" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secret_access" {
  statement {
    sid       = "ReadNetbirdSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.secret_arns
  }

  # Needed once the secrets use a customer-managed key (the expected case).
  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid       = "DecryptSecretsKey"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "execution_secret_access" {
  name   = "netbird-secrets-read"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secret_access.json
}

# Task role: EFS client access through IAM authorization, scoped to this
# module's access points (defense in depth on top of the SG boundary).
data "aws_iam_policy_document" "task_efs_access" {
  statement {
    sid    = "EfsClientAccess"
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
    ]
    resources = [aws_efs_file_system.this.arn]
    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values   = concat([aws_efs_access_point.data.arn], aws_efs_access_point.acme[*].arn)
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-ecs-task"
  })
}

resource "aws_iam_role_policy" "task_efs_access" {
  name   = "efs-client-access"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_efs_access.json
}

###############################################################################
# CloudWatch Logs
###############################################################################

resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_158: "KMS encryption optional; controlled via var.kms_key_arn"
  # checkov:skip=CKV_AWS_338: "Retention varies by environment; default var.log_retention_days=30 (same convention as mempalace_server)"
  name              = "/ecs/${var.cluster_name}/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(local.common_tags, {
    "Name" = "/ecs/${var.cluster_name}/${local.name_prefix}"
  })
}

###############################################################################
# Task Definition
###############################################################################

resource "aws_ecs_task_definition" "this" {
  # checkov:skip=CKV_AWS_336: "config-init runs with a read-only root. The others stay writable: the dashboard image rewrites its own nginx config and JS env at startup, and netbird-server and Traefik are untested read-only. Revisit after the ADR-037 spike."
  family                   = local.name_prefix
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # Task-local ephemeral volume shared by config-init (writer), the server
  # and Traefik (readers). No host path on Fargate: this is a bind mount on
  # the task's own encrypted ephemeral storage.
  volume {
    name = "config"
  }

  volume {
    name = "netbird-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.data.id
        iam             = "ENABLED"
      }
    }
  }

  dynamic "volume" {
    for_each = local.traefik_tls ? [1] : []
    content {
      name = "traefik-acme"
      efs_volume_configuration {
        file_system_id     = aws_efs_file_system.this.id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = aws_efs_access_point.acme[0].id
          iam             = "ENABLED"
        }
      }
    }
  }

  container_definitions = jsonencode([
    {
      name                   = "config-init"
      image                  = var.traefik_image
      essential              = false
      readonlyRootFilesystem = true # writes only to the /config volume
      entryPoint             = ["/bin/sh", "-c"]
      command                = [local.init_script]
      environment = [
        { name = "NB_CONFIG_YAML", value = local.netbird_config },
        { name = "TRAEFIK_DYNAMIC_YAML", value = local.traefik_dynamic },
      ]
      secrets = local.seed_owner ? [
        { name = "NB_OWNER_EMAIL", valueFrom = "${var.owner_secret_arn}:email::" },
        { name = "NB_OWNER_PASSWORD", valueFrom = "${var.owner_secret_arn}:password::" },
      ] : []
      mountPoints = [
        { sourceVolume = "config", containerPath = "/config", readOnly = false }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options, { "awslogs-stream-prefix" = "config-init" })
      }
    },
    {
      name      = "netbird-server"
      image     = var.netbird_server_image
      essential = true
      # Image default command is already ["--config", "/etc/netbird/config.yaml"].
      dependsOn = [
        { containerName = "config-init", condition = "SUCCESS" }
      ]
      portMappings = concat(
        [
          { containerPort = var.server_port, protocol = "tcp" },
          { containerPort = var.health_port, protocol = "tcp" },
        ],
        local.embedded_stun ? [
          { containerPort = var.stun_port, protocol = "udp" }
        ] : [],
      )
      secrets = [
        { name = "NB_AUTH_SECRET", valueFrom = var.auth_secret_arn },
        { name = "NB_STORE_ENCRYPTION_KEY", valueFrom = var.store_encryption_key_secret_arn },
        { name = "NB_IDP_SESSION_COOKIE_ENCRYPTION_KEY", valueFrom = var.session_cookie_key_secret_arn },
      ]
      mountPoints = [
        { sourceVolume = "config", containerPath = "/etc/netbird", readOnly = true },
        { sourceVolume = "netbird-data", containerPath = "/var/lib/netbird", readOnly = false },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options, { "awslogs-stream-prefix" = "netbird-server" })
      }
    },
    {
      name        = "dashboard"
      image       = var.dashboard_image
      essential   = true
      environment = local.dashboard_environment
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options, { "awslogs-stream-prefix" = "dashboard" })
      }
    },
    {
      name      = "traefik"
      image     = var.traefik_image
      essential = true
      command   = local.traefik_command
      dependsOn = [
        { containerName = "config-init", condition = "SUCCESS" },
        { containerName = "netbird-server", condition = "START" },
      ]
      portMappings = [
        { containerPort = var.https_port, protocol = "tcp" }
      ]
      mountPoints = concat(
        [
          { sourceVolume = "config", containerPath = "/config", readOnly = true }
        ],
        local.traefik_tls ? [
          { sourceVolume = "traefik-acme", containerPath = "/letsencrypt", readOnly = false }
        ] : [],
      )
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.log_options, { "awslogs-stream-prefix" = "traefik" })
      }
    },
  ])

  lifecycle {
    precondition {
      condition     = !local.traefik_tls || var.acme_email != null
      error_message = "acme_email is required when tls_mode is \"traefik\"."
    }
    precondition {
      condition     = local.embedded_stun || var.stun_target_group_arn == null
      error_message = "stun_target_group_arn must be null when stun_servers is set (embedded STUN is disabled)."
    }
  }

  tags = merge(local.common_tags, {
    "Name" = local.name_prefix
  })
}

###############################################################################
# ECS Service
###############################################################################

resource "aws_ecs_service" "this" {
  # checkov:skip=CKV_AWS_333: "assign_public_ip default true is deliberate (ADR-037, no-NAT cost pattern from ADR-034/ADR-031); task SG accepts TCP only from the load balancer SG"
  name            = local.name_prefix
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Stop-then-start: SQLite on EFS must never have two writers, which a
  # default rolling deployment (new task up before old task down) creates.
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  health_check_grace_period_seconds = var.https_target_group_arn != null || var.stun_target_group_arn != null ? 120 : null

  depends_on = [aws_efs_mount_target.this]

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [module.task_sg.id]
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.https_target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.https_target_group_arn
      container_name   = "traefik"
      container_port   = var.https_port
    }
  }

  dynamic "load_balancer" {
    for_each = var.stun_target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.stun_target_group_arn
      container_name   = "netbird-server"
      container_port   = var.stun_port
    }
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  propagate_tags = "TASK_DEFINITION"

  lifecycle {
    ignore_changes = [
      desired_count, # Managed by the toggle/lease workflows, same as mempalace_server
    ]
  }

  tags = merge(local.common_tags, {
    "Name" = local.name_prefix
  })
}
