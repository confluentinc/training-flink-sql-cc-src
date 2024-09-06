variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_provider" {
  description = "Cloud Provider (AWS, GCP, AZURE)"
  type        = string
}

variable "confluent_cloud_region" {
  description = "Cloud region ID based on the provider"
  type        = string
}
