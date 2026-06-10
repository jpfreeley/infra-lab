variable "alarms" {
  description = "List of alarm definitions"
  type = list(object({
    name                = string
    description         = string
    comparison_operator = string
    evaluation_periods  = number
    metric_name         = string
    namespace           = string
    period              = number
    statistic           = string
    threshold           = number
    treat_missing_data  = optional(string, "missing")
    dimensions          = optional(map(string), {})
  }))
}

variable "alarm_actions" {
  description = "ARNs of actions for ALARM state (SNS topics)"
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "ARNs of actions for OK state"
  type        = list(string)
  default     = []
}

variable "project" {
  description = "Project name for tagging"
  type        = string
  default     = "infra-lab"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
