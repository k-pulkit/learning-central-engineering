variable "region" {
  type        = string
  description = "Region to deploy services"
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "Tags for resources"
}