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

resource "confluent_environment" "trading-env" {
  display_name = "Trading-Env"

  stream_governance {
    package = "ESSENTIALS"
  }
}

data "confluent_schema_registry_cluster" "essentials" {
  environment {
    id = confluent_environment.trading-env.id
  }

  depends_on = [
    confluent_kafka_cluster.basic
  ]
}

resource "confluent_kafka_cluster" "basic" {
  display_name = "trading-kafka"
  availability = "SINGLE_ZONE"
  cloud        = var.confluent_cloud_provider
  region       = var.confluent_cloud_region
  basic {}
  environment {
    id = confluent_environment.trading-env.id
  }
}

resource "confluent_service_account" "app-manager" {
  display_name = "app-trading-manager"
  description  = "Service account to manage 'trading-kafka' Kafka cluster"
}

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
}

resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "app-trading-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-trading-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.trading-env.id
    }
  }

  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin
  ]
}

resource "confluent_kafka_topic" "stock_trades" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name    = "stock_trades"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}


resource "confluent_service_account" "app-connector" {
  display_name = "app-trading-connector"
  description  = "Service account of Stock Trades Datagen Connector"
}


resource "confluent_kafka_acl" "app-connector-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-target-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.stock_trades.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_connector" "source" {
  environment {
    id = confluent_environment.trading-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  config_sensitive = {}

  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "Stock_Trades_DatagenSourceConnector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    "kafka.topic"              = confluent_kafka_topic.stock_trades.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "STOCK_TRADES"
    "tasks.max"                = "1"
  }

  depends_on = [
    data.confluent_schema_registry_cluster.essentials,
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-write-on-target-topic,
  ]
}


resource "confluent_service_account" "statements-runner" {
  display_name = "trading-statements-runner"
  description  = "Service account for running Flink Statements in 'trading-kafka' Kafka cluster"
}

resource "confluent_role_binding" "statements-runner-environment-admin" {
  principal   = "User:${confluent_service_account.statements-runner.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.trading-env.resource_name
}

resource "confluent_role_binding" "app-manager-assigner" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.main.resource_name}/service-account=${confluent_service_account.statements-runner.id}"
}

resource "confluent_role_binding" "app-manager-flink-developer" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.trading-env.resource_name
}

resource "confluent_api_key" "app-manager-flink-api-key" {
  display_name = "app-trading-manager-flink-api-key"
  description  = "Flink API Key that is owned by 'app-trading-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }
  managed_resource {
    id          = data.confluent_flink_region.region.id
    api_version = data.confluent_flink_region.region.api_version
    kind        = data.confluent_flink_region.region.kind
    environment {
      id = confluent_environment.trading-env.id
    }
  }
}

data "confluent_flink_region" "region" {
  cloud   = var.confluent_cloud_provider
  region  = var.confluent_cloud_region
}

resource "confluent_flink_compute_pool" "main" {
  display_name = "trading-compute-pool"
  cloud        = var.confluent_cloud_provider
  region       = var.confluent_cloud_region
  max_cfu      = 10
  environment {
    id = confluent_environment.trading-env.id
  }
  depends_on = [
    confluent_role_binding.statements-runner-environment-admin,
    confluent_role_binding.app-manager-assigner,
    confluent_role_binding.app-manager-flink-developer,
    confluent_api_key.app-manager-flink-api-key,
  ]
}
