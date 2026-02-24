output "resource-ids" {
  value = <<-EOT
  Environment ID:   ${confluent_environment.advanced-env.id}
  Kafka Cluster ID: ${confluent_kafka_cluster.basic.id}
  Kafka topic (orders): ${confluent_kafka_topic.orders.topic_name}

  Service Accounts and their Kafka API Keys (API Keys inherit the permissions granted to the owner):
  ${confluent_service_account.app-advanced-manager.display_name}:                     ${confluent_service_account.app-advanced-manager.id}
  ${confluent_service_account.app-advanced-manager.display_name}'s Kafka API Key:     "${confluent_api_key.app-advanced-manager-kafka-api-key.id}"
  ${confluent_service_account.app-advanced-manager.display_name}'s Kafka API Secret:  "${confluent_api_key.app-advanced-manager-kafka-api-key.secret}"
  EOT

  sensitive = true
}
