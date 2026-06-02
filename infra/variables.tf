variable "prefix" {
  description = "Short prefix for all resource names. Lowercase, 3-8 chars."
  type        = string
  default     = "jobasst"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus2"
}

variable "openai_model" {
  description = "OpenAI model to use."
  type        = string
  default     = "gpt-4o"
}

variable "tags" {
  type = map(string)
  default = {
    project     = "job-application-helper"
    environment = "dev"
    managed-by  = "terraform"
  }
}
