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

resource "confluent_environment" "advanced-env" {
  display_name = "Advanced-Env"

  stream_governance {
    package = "ESSENTIALS"
  }
}

data "confluent_schema_registry_cluster" "essentials" {
  environment {
    id = confluent_environment.advanced-env.id
  }

  depends_on = [
    confluent_kafka_cluster.basic
  ]
}

resource "confluent_kafka_cluster" "basic" {
  display_name = "advanced-kafka"
  availability = "SINGLE_ZONE"
  cloud        = var.confluent_cloud_provider
  region       = var.confluent_cloud_region
  basic {}
  environment {
    id = confluent_environment.advanced-env.id
  }
}

resource "confluent_service_account" "app-advanced-manager" {
  display_name = "app-advanced-manager"
  description  = "Service account to manage 'advanced-kafka' Kafka cluster"
}

resource "confluent_role_binding" "app-advanced-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-advanced-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
}

resource "confluent_api_key" "app-advanced-manager-kafka-api-key" {
  display_name = "app-advanced-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-advanced-manager' service account"
  owner {
    id          = confluent_service_account.app-advanced-manager.id
    api_version = confluent_service_account.app-advanced-manager.api_version
    kind        = confluent_service_account.app-advanced-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.advanced-env.id
    }
  }

  depends_on = [
    confluent_role_binding.app-advanced-manager-kafka-cluster-admin
  ]
}

resource "confluent_kafka_topic" "orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name         = "orders"
  partitions_count   = 3
  rest_endpoint      = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-advanced-manager-kafka-api-key.id
    secret = confluent_api_key.app-advanced-manager-kafka-api-key.secret
  }
}

resource "confluent_service_account" "app-advanced-connector" {
  display_name = "app-advanced-connector"
  description  = "Service account of Datagen Connector"
}

resource "confluent_kafka_acl" "app-advanced-connector-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-advanced-connector.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-advanced-manager-kafka-api-key.id
    secret = confluent_api_key.app-advanced-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-advanced-connector-write-on-orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.orders.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-advanced-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-advanced-manager-kafka-api-key.id
    secret = confluent_api_key.app-advanced-manager-kafka-api-key.secret
  }
}

resource "confluent_connector" "source_orders" {
  environment {
    id = confluent_environment.advanced-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {}

  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "Orders_DatagenSourceConnector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-advanced-connector.id
    "kafka.topic"              = confluent_kafka_topic.orders.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "ORDERS"
    "tasks.max"                = "1"
  }

  depends_on = [
    data.confluent_schema_registry_cluster.essentials,
    confluent_kafka_acl.app-advanced-connector-describe-on-cluster,
    confluent_kafka_acl.app-advanced-connector-write-on-orders,
  ]
}

resource "confluent_service_account" "advanced-statements-runner" {
  display_name = "advanced-statements-runner"
  description  = "Service account for running Flink Statements in 'advanced-kafka' Kafka cluster"
}

resource "confluent_role_binding" "advanced-statements-runner-environment-admin" {
  principal   = "User:${confluent_service_account.advanced-statements-runner.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.advanced-env.resource_name
}

resource "confluent_role_binding" "app-advanced-manager-assigner" {
  principal   = "User:${confluent_service_account.app-advanced-manager.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.main.resource_name}/service-account=${confluent_service_account.advanced-statements-runner.id}"
}

resource "confluent_role_binding" "app-advanced-manager-flink-developer" {
  principal   = "User:${confluent_service_account.app-advanced-manager.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.advanced-env.resource_name
}

resource "confluent_api_key" "app-advanced-manager-flink-api-key" {
  display_name = "app-advanced-manager-flink-api-key"
  description  = "Flink API Key that is owned by 'app-advanced-manager' service account"
  owner {
    id          = confluent_service_account.app-advanced-manager.id
    api_version = confluent_service_account.app-advanced-manager.api_version
    kind        = confluent_service_account.app-advanced-manager.kind
  }
  managed_resource {
    id          = data.confluent_flink_region.region.id
    api_version = data.confluent_flink_region.region.api_version
    kind        = data.confluent_flink_region.region.kind
    environment {
      id = confluent_environment.advanced-env.id
    }
  }
}

data "confluent_flink_region" "region" {
  cloud   = var.confluent_cloud_provider
  region  = var.confluent_cloud_region
}

resource "confluent_flink_compute_pool" "main" {
  display_name = "advanced-compute-pool"
  cloud        = var.confluent_cloud_provider
  region       = var.confluent_cloud_region
  max_cfu      = 10
  environment {
    id = confluent_environment.advanced-env.id
  }
  depends_on = [
    confluent_role_binding.advanced-statements-runner-environment-admin,
    confluent_role_binding.app-advanced-manager-assigner,
    confluent_role_binding.app-advanced-manager-flink-developer,
    confluent_api_key.app-advanced-manager-flink-api-key,
  ]
}
