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
