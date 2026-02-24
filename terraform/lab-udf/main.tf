terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.24.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

data "confluent_organization" "main" {}

resource "confluent_environment" "udf-env" {
  display_name = "UDF-Env"

  stream_governance {
    package = "ESSENTIALS"
  }
}

data "confluent_schema_registry_cluster" "essentials" {
  environment {
    id = confluent_environment.udf-env.id
  }

  depends_on = [
    confluent_kafka_cluster.basic
  ]
}

resource "confluent_kafka_cluster" "basic" {
  display_name = "udf-kafka"
  availability = "SINGLE_ZONE"
  cloud        = var.confluent_cloud_provider
  region       = var.confluent_cloud_region
  basic {}
  environment {
    id = confluent_environment.udf-env.id
  }
}

// ----- Service accounts & API keys -----

resource "confluent_service_account" "app-udf-manager" {
  display_name = "app-udf-manager"
  description  = "Service account to manage 'udf-kafka' Kafka cluster"
}

resource "confluent_role_binding" "app-udf-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-udf-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
}

resource "confluent_api_key" "app-udf-manager-kafka-api-key" {
  display_name = "app-udf-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-udf-manager' service account"
  owner {
    id          = confluent_service_account.app-udf-manager.id
    api_version = confluent_service_account.app-udf-manager.api_version
    kind        = confluent_service_account.app-udf-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.udf-env.id
    }
  }

  depends_on = [
    confluent_role_binding.app-udf-manager-kafka-cluster-admin
  ]
}

// ----- Topics -----

resource "confluent_kafka_topic" "credit_cards" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name    = "credit_cards"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-udf-manager-kafka-api-key.id
    secret = confluent_api_key.app-udf-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_topic" "transactions" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name    = "transactions"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-udf-manager-kafka-api-key.id
    secret = confluent_api_key.app-udf-manager-kafka-api-key.secret
  }
}

// ----- Connector service account & ACLs -----

resource "confluent_service_account" "app-udf-connector" {
  display_name = "app-udf-connector"
  description  = "Service account of Datagen Connectors for UDF lab"
}

resource "confluent_kafka_acl" "app-udf-connector-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-udf-connector.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-udf-manager-kafka-api-key.id
    secret = confluent_api_key.app-udf-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-udf-connector-write-credit-cards" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.credit_cards.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-udf-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-udf-manager-kafka-api-key.id
    secret = confluent_api_key.app-udf-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-udf-connector-write-transactions" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.transactions.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-udf-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-udf-manager-kafka-api-key.id
    secret = confluent_api_key.app-udf-manager-kafka-api-key.secret
  }
}

// ----- Datagen Connectors -----

resource "confluent_connector" "source_credit_cards" {
  environment {
    id = confluent_environment.udf-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {}

  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "Credit_Cards_DatagenSourceConnector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-udf-connector.id
    "kafka.topic"              = confluent_kafka_topic.credit_cards.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "CREDIT_CARDS"
    "tasks.max"                = "1"
  }

  depends_on = [
    data.confluent_schema_registry_cluster.essentials,
    confluent_kafka_acl.app-udf-connector-describe-on-cluster,
    confluent_kafka_acl.app-udf-connector-write-credit-cards,
  ]
}

resource "confluent_connector" "source_transactions" {
  environment {
    id = confluent_environment.udf-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {}

  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "Transactions_DatagenSourceConnector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-udf-connector.id
    "kafka.topic"              = confluent_kafka_topic.transactions.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "TRANSACTIONS"
    "tasks.max"                = "1"
  }

  depends_on = [
    data.confluent_schema_registry_cluster.essentials,
    confluent_kafka_acl.app-udf-connector-describe-on-cluster,
    confluent_kafka_acl.app-udf-connector-write-transactions,
  ]
}

// ----- Flink Compute Pool -----

resource "confluent_service_account" "udf-statements-runner" {
  display_name = "udf-statements-runner"
  description  = "Service account for running Flink Statements in 'udf-kafka' Kafka cluster"
}

resource "confluent_role_binding" "udf-statements-runner-environment-admin" {
  principal   = "User:${confluent_service_account.udf-statements-runner.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.udf-env.resource_name
}

resource "confluent_role_binding" "app-udf-manager-assigner" {
  principal   = "User:${confluent_service_account.app-udf-manager.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.main.resource_name}/service-account=${confluent_service_account.udf-statements-runner.id}"
}

resource "confluent_role_binding" "app-udf-manager-flink-developer" {
  principal   = "User:${confluent_service_account.app-udf-manager.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.udf-env.resource_name
}

resource "confluent_api_key" "app-udf-manager-flink-api-key" {
  display_name = "app-udf-manager-flink-api-key"
  description  = "Flink API Key that is owned by 'app-udf-manager' service account"
  owner {
    id          = confluent_service_account.app-udf-manager.id
    api_version = confluent_service_account.app-udf-manager.api_version
    kind        = confluent_service_account.app-udf-manager.kind
  }
  managed_resource {
    id          = data.confluent_flink_region.region.id
    api_version = data.confluent_flink_region.region.api_version
    kind        = data.confluent_flink_region.region.kind
    environment {
      id = confluent_environment.udf-env.id
    }
  }
}

data "confluent_flink_region" "region" {
  cloud  = var.confluent_cloud_provider
  region = var.confluent_cloud_region
}

resource "confluent_flink_compute_pool" "main" {
  display_name = "udf-compute-pool"
  cloud        = var.confluent_cloud_provider
  region       = var.confluent_cloud_region
  max_cfu      = 10
  environment {
    id = confluent_environment.udf-env.id
  }
  depends_on = [
    confluent_role_binding.udf-statements-runner-environment-admin,
    confluent_role_binding.app-udf-manager-assigner,
    confluent_role_binding.app-udf-manager-flink-developer,
    confluent_api_key.app-udf-manager-flink-api-key,
  ]
}
