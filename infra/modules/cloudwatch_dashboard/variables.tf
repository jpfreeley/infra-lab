variable "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  type        = string
}

variable "dashboard_body_json" {
  description = "JSON body of the dashboard (CloudWatch Dashboard format)"
  type        = string
}
