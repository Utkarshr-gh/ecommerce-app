variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "app_name_prefix" {
  type    = string
  default = "ecomm"
}

variable "app_service_sku" {
  type    = string
  default = "B1" # Basic is the minimum that supports VNet integration and private endpoints
}

variable "ssl_pfx_path" {
  type        = string
  default     = ""
  description = "Path to a .pfx certificate. Leave empty to deploy HTTP only; set it to enable the HTTPS listener and the HTTP-to-HTTPS redirect."
}

variable "ssl_pfx_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Password of the .pfx file. Pass it with -var or an environment variable, never commit it."
}
