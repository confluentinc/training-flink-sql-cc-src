output "resource-ids" {
  value = <<-EOT
  Environment ID:   ${confluent_environment.udf-env.id}
  Kafka Cluster ID: ${confluent_kafka_cluster.basic.id}
  Kafka topic (credit_cards): ${confluent_kafka_topic.credit_cards.topic_name}
  Kafka topic (transactions): ${confluent_kafka_topic.transactions.topic_name}

  Service Accounts and their Kafka API Keys (API Keys inherit the permissions granted to the owner):
  ${confluent_service_account.app-udf-manager.display_name}:                     ${confluent_service_account.app-udf-manager.id}
  ${confluent_service_account.app-udf-manager.display_name}'s Kafka API Key:     "${confluent_api_key.app-udf-manager-kafka-api-key.id}"
  ${confluent_service_account.app-udf-manager.display_name}'s Kafka API Secret:  "${confluent_api_key.app-udf-manager-kafka-api-key.secret}"
  EOT

  sensitive = true
}
