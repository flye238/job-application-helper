# AI assistance: Claude was used to help generate/debug portions
# of this implementation. All AI-generated suggestions were reviewed and modified
# by the author.

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

variable "github_sp_object_id" {
  description = "Object ID of the GitHub Actions service principal. Required for ACR push access."
  type        = string
  default     = "589f0ba6-c27f-4752-81a4-202ea77d0ad9"
}

variable "tags" {
  type = map(string)
  default = {
    project     = "job-application-helper"
    environment = "dev"
    managed-by  = "terraform"
  }
}
