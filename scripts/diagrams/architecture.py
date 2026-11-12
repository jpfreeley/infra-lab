"""Generate the infra-lab architecture diagram (one 17 x 11 in landscape page).

Writes docs/diagrams/infra-lab-architecture.svg and .html. The SVG is the source
for the PDF and PNG, which are rendered with headless Chrome:

    python3 scripts/diagrams/architecture.py
    CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    "$CHROME" --headless=new --no-pdf-header-footer \
        --print-to-pdf=docs/diagrams/infra-lab-architecture.pdf docs/diagrams/infra-lab-architecture.html
    "$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=2 --window-size=1632,1056 \
        --screenshot=docs/diagrams/infra-lab-architecture.png docs/diagrams/infra-lab-architecture.html

The content is hand-maintained: update it when an ADR or a live root changes what
is deployed. Account IDs and hostnames stay out of the diagram on purpose.
"""
from html import escape
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parents[2] / "docs" / "diagrams"

W, H = 1700, 1100
out = []

C = {
    "ink": "#1f2933", "muted": "#5f6b7a", "line": "#c5ccd6", "frame": "#8a96a6",
    "gov": "#2f5fa7", "gov_bg": "#eef3fb",
    "net": "#0f7b6c", "net_bg": "#ecf7f5",
    "app": "#6b46c1", "app_bg": "#f4f0fc",
    "ops": "#b7791f", "ops_bg": "#fdf6e9",
    "ci": "#24292f", "ci_bg": "#f3f4f6",
    "off": "#9aa5b1", "off_bg": "#f7f8fa",
}


def rect(x, y, w, h, stroke, fill="none", dash=None, r=8, sw=1.4):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')


def text(x, y, s, size=12, color=None, weight=400, anchor="start", italic=False):
    st = ' font-style="italic"' if italic else ""
    out.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{color or C["ink"]}" font-weight="{weight}" text-anchor="{anchor}"{st}>{escape(s)}</text>')


def lines(x, y, items, size=12, gap=None, color=None, bullet=False):
    gap = gap or round(size * 1.38)
    for i, s in enumerate(items):
        if s.startswith("   "):
            text(x + (9 if bullet else 10), y + i * gap, s.strip(), size, color)
        else:
            text(x, y + i * gap, ("• " if bullet else "") + s, size, color)
    return y + len(items) * gap


def card(x, y, w, h, title, body, color, bg, dash=None, size=11.5, title_size=12.5, status=None):
    if dash == "off":
        rect(x, y, w, h, C["off"], C["off_bg"], "2 4")
        tc = C["muted"]
    else:
        rect(x, y, w, h, color, bg, dash)
        tc = color
    text(x + 10, y + 19, title, title_size, tc, 700)
    if status:
        text(x + w - 10, y + 19, status, 10, C["muted"], 600, "end", italic=True)
    lines(x + 10, y + 38, body, size, color=C["ink"] if dash != "off" else C["muted"])


def marker(color):
    # One arrowhead per colour: context-stroke is not supported everywhere.
    return "ah-" + color.lstrip("#")


def arrow(x1, y1, x2, y2, label=None, color=None, lx=None, ly=None, dash=None, anchor="middle"):
    color = color or C["muted"]
    d = f' stroke-dasharray="{dash}"' if dash else ""
    out.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="1.6" marker-end="url(#{marker(color)})"{d}/>')
    if label:
        text(lx if lx is not None else (x1 + x2) / 2, ly if ly is not None else (y1 + y2) / 2 - 6, label, 10.5, color, 600, anchor)


def poly(points, label=None, lx=0, ly=0, color=None, anchor="start"):
    color = color or C["muted"]
    pts = " ".join(f"{a},{b}" for a, b in points)
    out.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="1.6" marker-end="url(#{marker(color)})"/>')
    if label:
        text(lx, ly, label, 10.5, color, 600, anchor)


# ── Title and legend ────────────────────────────────────────────────────────
text(30, 52, "infra-lab: multi-account AWS platform", 28, C["ink"], 700)
text(30, 78, "Terraform IaC (20 reusable modules, 36 ADRs)  ·  GitHub Actions with keyless OIDC  ·  AWS Organizations + Control Tower  ·  us-east-1 (us-west-2 for replicas)", 13.5, C["muted"])

lx = 1185
rect(lx, 24, 485, 66, C["line"], "#ffffff", r=6)
rect(lx + 14, 36, 34, 16, C["net"], C["net_bg"], r=3)
text(lx + 56, 49, "Deployed baseline", 11.5)
rect(lx + 14, 62, 34, 16, C["app"], C["app_bg"], "6 4", r=3)
text(lx + 56, 75, "On demand / scales to zero", 11.5)
rect(lx + 245, 36, 34, 16, C["off"], C["off_bg"], "2 4", r=3)
text(lx + 287, 49, "Defined in code, not deployed", 11.5)
text(lx + 245, 75, "Account IDs and hostnames omitted", 11.5, C["muted"], italic=True)

# ── Left column: delivery and access ───────────────────────────────────────
text(30, 128, "DELIVERY AND ACCESS", 12, C["muted"], 700)

card(30, 140, 270, 96, "GitHub monorepo", [
    "infra/  modules, live roots, mgmt", "app/  ·  docs/ (ADRs, runbooks)", "scripts/  ·  web/ (backlog)",
], C["ci"], C["ci_bg"])
arrow(165, 236, 165, 258)
card(30, 260, 270, 182, "GitHub Actions CI gates", [
    "terraform fmt / validate / plan", "tflint", "checkov (IaC security)", "terraform-compliance",
    "   (tagging policy as code)", "gitleaks secret scanning", "shellcheck · markdownlint",
    "pre-commit parity with CI (ADR-028)",
], C["ci"], C["ci_bg"])
arrow(165, 442, 165, 492)
text(175, 471, "assume role", 10.5, C["gov"], 600)
card(30, 494, 270, 76, "OIDC federation (ADR-009)", [
    "Short-lived STS credentials", "No stored AWS keys in GitHub",
], C["gov"], C["gov_bg"])

card(30, 600, 270, 96, "Engineer access", [
    "IAM Identity Center (SSO)", "5 permission sets: Admin, Platform,", "Developer, SecurityAuditor, ReadOnly",
], C["gov"], C["gov_bg"])

text(30, 728, "DESIGN PRINCIPLES", 12, C["muted"], 700)
lines(30, 750, [
    "No IAM users or access keys (SCP)",
    "Guardrails by OU, service boundary",
    "   SCPs on single-purpose accounts",
    "Compute off by default in dev",
    "   (ADR-030); workers scale from 0",
    "Execution plane cannot reach the",
    "   control plane except HTTPS",
    "Encryption with customer KMS keys",
    "TLS-only S3 bucket policies",
    "Tag-based cost allocation, budgets,",
    "   anomaly alerts and backups",
    "Every decision recorded as an ADR",
], 11.5, gap=17, bullet=True)

# arrows into the org
poly([(300, 532), (318, 532)], color=C["gov"])
poly([(300, 648), (318, 648)], color=C["gov"])

# ── AWS Organization frame ─────────────────────────────────────────────────
rect(320, 108, 1360, 966, C["frame"], "#ffffff", "8 5", r=12, sw=1.6)
text(338, 130, "AWS ORGANIZATION", 12, C["frame"], 700)

# Management account
rect(338, 140, 1326, 620, C["gov"], "none", r=10, sw=1.6)
text(354, 163, "Management account", 15, C["gov"], 700)
text(530, 163, "governance and state backend; the dev / staging / prod environments are defined here too (lab cost choice)", 12, C["muted"])

gy, gh, gw, gx0, gg = 176, 150, 255, 354, 6.5
gov_cards = [
    ("Organizations + Control Tower", ["Landing zone, 4 OUs", "SCPs: deny IAM users, root,", "leaving org, disabling security", "services, unapproved regions", "Tag and backup policies"]),
    ("Security services (org-wide)", ["CloudTrail org trail (KMS)", "AWS Config aggregator +", "conformance pack", "GuardDuty, Security Hub", "(CIS + FSBP), Access Analyzer"]),
    ("Identity", ["IAM Identity Center", "GitHub OIDC provider", "+ deploy role", "Strict password policy", "Cross-account audit role"]),
    ("FinOps", ["Org monthly budget", "Cost Anomaly Detection", "-> SNS (customer KMS key)", "Email alert subscriptions", "Tag-based cost allocation"]),
    ("Terraform state backend", ["S3, versioned, KMS, TLS-only", "Cross-region replica", "DynamoDB state locks", "Access-logged log buckets", "One state key per root"]),
]
for i, (t, b) in enumerate(gov_cards):
    card(gx0 + i * (gw + gg), gy, gw, gh, t, b, C["gov"], C["gov_bg"], size=11.5)

# Environments band
ey = 342
text(354, ey + 6, "WORKLOAD ENVIRONMENTS", 12, C["net"], 700)
text(540, ey + 6, "one control-plane VPC + one execution-plane VPC per environment, joined by VPC peering", 12, C["muted"])

# dev: only the scheduled Lambdas and their secrets are in state today; the
# VPC pair and everything inside it is code only (checked against state 2026-11-12).
rect(354, ey + 16, 950, 390, C["frame"], "none", r=10, sw=1.4)
text(368, ey + 37, "dev", 14, C["net"], 700)
text(400, ey + 37, "VPC pair and workloads defined in code, not deployed. Live today: scheduled Lambdas and their secrets.", 12, C["muted"])
OFF = (C["off"], C["off_bg"], "off")

# Control VPC
cx, cy, cw, ch = 368, ey + 46, 427, 262
k = (cw - 30) / 2
rect(cx, cy, cw, ch, C["off"], "#ffffff", "2 4", r=8)
text(cx + 10, cy + 19, "Control-plane VPC  10.0.0.0/20", 12.5, C["muted"], 700)
text(cx + cw - 10, cy + 19, "private subnets, no NAT", 10.5, C["muted"], 600, "end", italic=True)
card(cx + 10, cy + 30, k, 74, "ALB (blue / green)", ["HTTPS :443, test :8443", "CodeDeploy traffic shift"], *OFF, size=11)
card(cx + 20 + k, cy + 30, k, 74, "ECS Fargate: API", ["CPU / memory autoscaling", "desired count 0 (ADR-030)"], *OFF, size=11)
arrow(cx + 10 + k, cy + 67, cx + 18 + k, cy + 67)
card(cx + 10, cy + 116, k, 74, "Step Functions", ["Job orchestrator", "retries, X-Ray tracing"], *OFF, size=11)
card(cx + 20 + k, cy + 116, k, 74, "SQS queues + DLQs", ["nano · medium · xlarge", "+ FIFO ordered queue"], *OFF, size=11)
arrow(cx + 10 + k, cy + 153, cx + 18 + k, cy + 153)
card(cx + 10, cy + 202, 280, 52, "Aurora Serverless v2 (Postgres 15)", ["0.5 to 4 ACU, auto-stop Lambda"], *OFF, size=11)
card(cx + 300, cy + 202, cw - 310, 52, "S3 gateway", ["endpoint"], *OFF, size=11)

# Execution VPC
gap = 64
xx, xw = cx + cw + gap, 427
rect(xx, cy, xw, ch, C["off"], "#ffffff", "2 4", r=8)
text(xx + 10, cy + 19, "Execution-plane VPC  10.0.16.0/20", 12.5, C["muted"], 700)
card(xx + 10, cy + 30, xw - 20, 74, "ECS Fargate worker tiers (scale from zero)", ["nano 0.25 vCPU  ·  medium 1 vCPU  ·  xlarge 4 vCPU", "one service and one queue per tier (ADR-014, ADR-020)"], *OFF, size=11)
card(xx + 10, cy + 116, xw - 20, 74, "Network ACL on private subnets", ["Deny egress to all RFC 1918 ranges", "Allow HTTPS to the control-plane VPC only"], *OFF, size=11)
card(xx + 10, cy + 202, 280, 52, "Aurora Serverless v2 (Postgres 15)", ["0.5 to 8 ACU, separate cluster"], *OFF, size=11)
card(xx + 300, cy + 202, xw - 310, 52, "S3 gateway", ["endpoint"], *OFF, size=11)

# workers -> control plane (results over HTTPS), queues -> workers (jobs)
mid = cx + cw + gap / 2
arrow(xx + 10, cy + 50, cx + cw - 8, cy + 50)
text(mid, cy + 44, "HTTPS", 10.5, C["muted"], 600, "middle")
poly([(cx + cw - 10, cy + 160), (mid, cy + 160), (mid, cy + 88), (xx + 8, cy + 88)])
text(mid, cy + 176, "jobs", 10.5, C["muted"], 600, "middle")
text(mid, cy + 236, "VPC", 10.5, C["muted"], 600, "middle")
text(mid, cy + 250, "peering", 10.5, C["muted"], 600, "middle")

# dev shared services row
sy = cy + ch + 26
dev_svcs = [
    ("Scheduled Lambdas", ["EventBridge Scheduler:", "idle teardown, batch job"], C["app"], C["app_bg"], None),
    ("Wake endpoint", ["Lambda function URL", "starts MemPalace"], C["app"], C["app_bg"], None),
    ("Secrets Manager", ["Lambda secrets", "KMS encrypted"], C["gov"], C["gov_bg"], None),
    ("S3 evidence bucket", ["KMS key, TLS-only", "versioned"], *OFF),
    ("CloudWatch + Backup", ["dashboard, alarms,", "tag-based backup"], *OFF),
    ("Flow logs + budgets", ["VPC flow logs", "per-env budgets"], *OFF),
]
dw = (918 - 5 * 8) / 6
for i, (t, b, col, bg, d) in enumerate(dev_svcs):
    card(368 + i * (dw + 8), sy, dw, 62, t, b, col, bg, d, size=11, title_size=12)

# staging / prod
px = 1318
card(px, ey + 16, 332, 180, "staging", [
    "Control VPC   10.0.32.0/20", "Execution VPC 10.0.48.0/20", "",
    "Same VPC-pair, NACL and endpoint", "code as dev. Network layer only.",
], C["off"], C["off_bg"], "off", size=11.5, title_size=14)
card(px, ey + 218, 332, 180, "prod", [
    "Control VPC   10.0.64.0/20", "Execution VPC 10.0.80.0/20", "",
    "Same VPC-pair, NACL and endpoint", "code as dev. Network layer only.",
], C["off"], C["off_bg"], "off", size=11.5, title_size=14)

# ── Bottom row: OUs and member accounts ────────────────────────────────────
by = 776
# Security OU
rect(338, by, 236, 286, C["gov"], "none", r=10)
text(352, by + 22, "Security OU", 14, C["gov"], 700)
card(352, by + 36, 208, 92, "Log Archive account", ["Control Tower managed", "Central CloudTrail and", "Config logs"], C["gov"], C["gov_bg"], size=11)
card(352, by + 138, 208, 104, "Audit account", ["Control Tower managed", "Delegated admin for", "GuardDuty and", "Security Hub"], C["gov"], C["gov_bg"], size=11)
text(352, by + 262, "Infrastructure + Sandbox OUs:", 10.5, C["muted"], 600)
text(352, by + 275, "guardrails attached, reserved", 10.5, C["muted"])

# Workloads OU
rect(588, by, 1076, 286, C["gov"], "none", r=10)
text(602, by + 22, "Workloads OU", 14, C["gov"], 700)
text(712, by + 22, "single-purpose accounts, each with a service-boundary SCP", 12, C["muted"])

# MemPalace account
mx, my, mw, mh = 602, by + 34, 640, 240
rect(mx, my, mw, mh, C["net"], C["net_bg"], r=8)
text(mx + 10, my + 20, "MemPalace account: shared MCP memory server (ADR-034)", 12.5, C["net"], 700)
text(mx + mw - 10, my + 20, "VPC 10.0.112.0/20", 10.5, C["muted"], 600, "end", italic=True)
card(mx + 10, my + 32, 150, 92, "Route 53 + ACM", ["Two hostnames", "TLS certificates"], C["net"], "#ffffff", size=11)
card(mx + 172, my + 32, 168, 92, "ALB + AWS WAF", ["HTTPS listener", "host-header rules", "bearer-token auth"], C["net"], "#ffffff", size=11)
card(mx + 352, my + 32, 278, 92, "ECS Fargate (one service per tenant)", ["MemPalace server + Qdrant per task,", "EFS per tenant, image pinned by", "digest. Second tenant currently off."], C["app"], "#ffffff", "6 4", size=11)
arrow(mx + 160, my + 78, mx + 170, my + 78, color=C["net"])
arrow(mx + 340, my + 78, mx + 350, my + 78, color=C["net"])
card(mx + 10, my + 136, 300, 98, "Idle teardown and wake", ["EventBridge Scheduler -> Lambda checks", "traffic; GitHub Actions scales to 0", "after 90 min idle. Self-serve wake", "via Lambda function URL."], C["app"], "#ffffff", size=11)
card(mx + 322, my + 136, 308, 98, "Ops and security", ["ALB access logs -> S3 -> Glue + Athena", "Customer KMS key, Secrets Manager", "tokens. About $35 to $40/mo running,", "about $1.40/mo torn down."], C["ops"], "#ffffff", size=11)

# Workspaces account
wx, ww = mx + mw + 12, 1664 - (mx + mw + 12) - 14
rect(wx, my, ww, mh, C["net"], C["net_bg"], r=8)
text(wx + 10, my + 20, "Workspaces account: dev desktops (ADR-031)", 12.5, C["net"], 700)
text(wx + ww - 10, my + 38, "VPC 10.0.96.0/20", 10.5, C["muted"], 600, "end", italic=True)
card(wx + 10, my + 46, ww - 20, 62, "Self-service API", ["API Gateway -> Lambda provisioner -> DynamoDB"], C["app"], "#ffffff", size=11)
card(wx + 10, my + 118, ww - 20, 62, "EC2 Spot desktop + NICE DCV", ["Browser IDE, Docker; idle stop at 30 min"], C["app"], "#ffffff", "6 4", size=11)
card(wx + 10, my + 190, ww - 20, 46, "Ollama GPU host (ADR-033)", ["dormant"], C["off"], C["off_bg"], "off", size=11)

# footer
text(30, 1090, "JP Freeley  ·  github.com/jpfreeley/infra-lab  ·  November 2026", 11, C["muted"])

markers = "".join(
    f'<marker id="{marker(c)}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>'
    for c in sorted({C["muted"], C["app"], C["net"], C["gov"]})
)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="17in" height="11in" font-family="-apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif">
<defs>{markers}</defs>
<rect width="{W}" height="{H}" fill="#ffffff"/>
{chr(10).join(out)}
</svg>'''

html = f'''<!doctype html><html><head><meta charset="utf-8"><title>infra-lab architecture</title>
<style>@page {{ size: 17in 11in; margin: 0; }} html,body {{ margin:0; padding:0; background:#fff; }} svg {{ display:block; }}</style>
</head><body>{svg}</body></html>'''
OUT_DIR.mkdir(parents=True, exist_ok=True)
(OUT_DIR / "infra-lab-architecture.svg").write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + svg + "\n")
(OUT_DIR / "infra-lab-architecture.html").write_text(html)
print(f"wrote {OUT_DIR}/infra-lab-architecture.svg and .html")
