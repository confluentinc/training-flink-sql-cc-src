terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "1.77.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

data "confluent_organization" "main" {}

resource "confluent_environment" "shoe-env" {
  display_name = "Shoe-Env"
}

# Stream Governance and Kafka clusters can be in different regions as well as different cloud providers,
# but you should to place both in the same cloud and region to restrict the fault isolation boundary.
data "confluent_schema_registry_region" "essentials" {
  cloud   = var.confluent_cloud_provider
  region  = var.confluent_cloud_region
  package = "ESSENTIALS"
}

resource "confluent_schema_registry_cluster" "essentials" {
  package = data.confluent_schema_registry_region.essentials.package

  environment {
    id = confluent_environment.shoe-env.id
  }

  region {
    # See https://docs.confluent.io/cloud/current/stream-governance/packages.html#stream-governance-regions
    id = data.confluent_schema_registry_region.essentials.id
  }
}

# Update the config to use a cloud provider and region of your choice.
# https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_kafka_cluster
resource "confluent_kafka_cluster" "basic" {
  display_name = "shoe-kafka"
  availability = "SINGLE_ZONE"
  cloud        = var.confluent_cloud_provider
  region       = var.confluent_cloud_region
  basic {}
  environment {
    id = confluent_environment.shoe-env.id
  }
}

// 'app-shoe-manager' service account is required in this configuration to create 'shoe' topics
resource "confluent_service_account" "app-shoe-manager" {
  display_name = "app-shoe-manager"
  description  = "Service account to manage 'shoe-kafka' Kafka cluster"
}

resource "confluent_role_binding" "app-shoe-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-shoe-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.basic.rbac_crn
}

resource "confluent_api_key" "app-shoe-manager-kafka-api-key" {
  display_name = "app-shoe-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-shoe-manager' service account"
  owner {
    id          = confluent_service_account.app-shoe-manager.id
    api_version = confluent_service_account.app-shoe-manager.api_version
    kind        = confluent_service_account.app-shoe-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.basic.id
    api_version = confluent_kafka_cluster.basic.api_version
    kind        = confluent_kafka_cluster.basic.kind

    environment {
      id = confluent_environment.shoe-env.id
    }
  }

  # The goal is to ensure that confluent_role_binding.app-shoe-manager-kafka-cluster-admin is created before
  # confluent_api_key.app-shoe-manager-kafka-api-key is used to create instances of
  # confluent_kafka_topic, confluent_kafka_acl resources.

  # 'depends_on' meta-argument is specified in confluent_api_key.app-shoe-manager-kafka-api-key to avoid having
  # multiple copies of this definition in the configuration which would happen if we specify it in
  # confluent_kafka_topic, confluent_kafka_acl resources instead.
  depends_on = [
    confluent_role_binding.app-shoe-manager-kafka-cluster-admin
  ]
}

resource "confluent_kafka_topic" "shoe_products" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name         = "shoe_products"
  partitions_count   = 3
  rest_endpoint      = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-shoe-manager-kafka-api-key.id
    secret = confluent_api_key.app-shoe-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_topic" "shoe_customers" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name         = "shoe_customers"
  partitions_count   = 3
  rest_endpoint      = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-shoe-manager-kafka-api-key.id
    secret = confluent_api_key.app-shoe-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_topic" "shoe_orders" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  topic_name         = "shoe_orders"
  partitions_count   = 3
  rest_endpoint      = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-shoe-manager-kafka-api-key.id
    secret = confluent_api_key.app-shoe-manager-kafka-api-key.secret
  }
}


resource "confluent_service_account" "app-shoe-connector" {
  display_name = "app-shoe-connector"
  description  = "Service account of Datagen Connector"
}


resource "confluent_kafka_acl" "app-shoe-connector-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-shoe-connector.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-shoe-manager-kafka-api-key.id
    secret = confluent_api_key.app-shoe-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-shoe-products-connector-write-on-target-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.shoe_products.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-shoe-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-shoe-manager-kafka-api-key.id
    secret = confluent_api_key.app-shoe-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-shoe-customers-connector-write-on-target-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.shoe_customers.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-shoe-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-shoe-manager-kafka-api-key.id
    secret = confluent_api_key.app-shoe-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-shoe-orders-connector-write-on-target-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.shoe_orders.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-shoe-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.basic.rest_endpoint
  credentials {
    key    = confluent_api_key.app-shoe-manager-kafka-api-key.id
    secret = confluent_api_key.app-shoe-manager-kafka-api-key.secret
  }
}

resource "confluent_connector" "source_shoe_products" {
  environment {
    id = confluent_environment.shoe-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_sensitive = {}

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "Shoe_Products_DatagenSourceConnector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-shoe-connector.id
    "kafka.topic"              = confluent_kafka_topic.shoe_products.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "SHOES"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_schema_registry_cluster.essentials,
    confluent_kafka_acl.app-shoe-connector-describe-on-cluster,
    confluent_kafka_acl.app-shoe-products-connector-write-on-target-topic,
  ]
}

resource "confluent_connector" "source_shoe_customers" {
  environment {
    id = confluent_environment.shoe-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_sensitive = {}

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "Shoe_Customers_DatagenSourceConnector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-shoe-connector.id
    "kafka.topic"              = confluent_kafka_topic.shoe_customers.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "SHOE_CUSTOMERS"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_schema_registry_cluster.essentials,
    confluent_kafka_acl.app-shoe-connector-describe-on-cluster,
    confluent_kafka_acl.app-shoe-customers-connector-write-on-target-topic,
  ]
}

resource "confluent_connector" "source_shoe_orders" {
  environment {
    id = confluent_environment.shoe-env.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.basic.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_sensitive = {}

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "Shoe_Orders_DatagenSourceConnector"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-shoe-connector.id
    "kafka.topic"              = confluent_kafka_topic.shoe_orders.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "SHOE_ORDERS"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_schema_registry_cluster.essentials,
    confluent_kafka_acl.app-shoe-connector-describe-on-cluster,
    confluent_kafka_acl.app-shoe-orders-connector-write-on-target-topic,
  ]
}


// Service account to perform a task within Confluent Cloud, such as executing a Flink statement
resource "confluent_service_account" "shoe-statements-runner" {
  display_name = "shoe-statements-runner"
  description  = "Service account for running Flink Statements in 'shoe-kafka' Kafka cluster"
}

resource "confluent_role_binding" "shoe-statements-runner-environment-admin" {
  principal   = "User:${confluent_service_account.shoe-statements-runner.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.shoe-env.resource_name
}

// https://docs.confluent.io/cloud/current/access-management/access-control/rbac/predefined-rbac-roles.html#assigner
// https://docs.confluent.io/cloud/current/flink/operate-and-deploy/flink-rbac.html#submit-long-running-statements
resource "confluent_role_binding" "app-shoe-manager-assigner" {
  principal   = "User:${confluent_service_account.app-shoe-manager.id}"
  role_name   = "Assigner"
  crn_pattern = "${data.confluent_organization.main.resource_name}/service-account=${confluent_service_account.shoe-statements-runner.id}"
}

// https://docs.confluent.io/cloud/current/access-management/access-control/rbac/predefined-rbac-roles.html#flinkadmin
resource "confluent_role_binding" "app-shoe-manager-flink-developer" {
  principal   = "User:${confluent_service_account.app-shoe-manager.id}"
  role_name   = "FlinkAdmin"
  crn_pattern = confluent_environment.shoe-env.resource_name
}

resource "confluent_api_key" "app-shoe-manager-flink-api-key" {
  display_name = "app-shoe-manager-flink-api-key"
  description  = "Flink API Key that is owned by 'app-shoe-manager' service account"
  owner {
    id          = confluent_service_account.app-shoe-manager.id
    api_version = confluent_service_account.app-shoe-manager.api_version
    kind        = confluent_service_account.app-shoe-manager.kind
  }
  managed_resource {
    id          = data.confluent_flink_region.region.id
    api_version = data.confluent_flink_region.region.api_version
    kind        = data.confluent_flink_region.region.kind
    environment {
      id = confluent_environment.shoe-env.id
    }
  }
}

data "confluent_flink_region" "region" {
  cloud   = var.confluent_cloud_provider
  region  = var.confluent_cloud_region
}

# https://docs.confluent.io/cloud/current/flink/get-started/quick-start-cloud-console.html#step-1-create-a-af-compute-pool
resource "confluent_flink_compute_pool" "main" {
  display_name = "shoe-compute-pool"
  cloud   = var.confluent_cloud_provider
  region  = var.confluent_cloud_region
  max_cfu      = 10
  environment {
    id = confluent_environment.shoe-env.id
  }
  depends_on = [
    confluent_role_binding.shoe-statements-runner-environment-admin,
    confluent_role_binding.app-shoe-manager-assigner,
    confluent_role_binding.app-shoe-manager-flink-developer,
    confluent_api_key.app-shoe-manager-flink-api-key,
  ]
}

resource "confluent_flink_statement" "create-table-customers_keyed" {
  organization {
    id = data.confluent_organization.main.id
  }

  environment {
    id = confluent_environment.shoe-env.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }

  principal {
    id = confluent_service_account.shoe-statements-runner.id
  }
  statement  = "CREATE TABLE shoe_customers_keyed (customer_id STRING,first_name STRING,last_name STRING,email STRING,PRIMARY KEY (customer_id) NOT ENFORCED) DISTRIBUTED INTO 1 BUCKETS;"
  properties = {
    "sql.current-catalog"  = confluent_environment.shoe-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.app-shoe-manager-flink-api-key.id
    secret = confluent_api_key.app-shoe-manager-flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    confluent_connector.source_shoe_products,
    confluent_connector.source_shoe_customers,
    confluent_connector.source_shoe_orders,
  ]
}

resource "confluent_flink_statement" "insert-into-customers_keyed" {
  organization {
    id = data.confluent_organization.main.id
  }

  environment {
    id = confluent_environment.shoe-env.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }

  principal {
    id = confluent_service_account.shoe-statements-runner.id
  }
  statement  = "INSERT INTO shoe_customers_keyed SELECT id,first_name,last_name,email FROM shoe_customers;"
  properties = {
    "sql.current-catalog"  = confluent_environment.shoe-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.app-shoe-manager-flink-api-key.id
    secret = confluent_api_key.app-shoe-manager-flink-api-key.secret
  }
  depends_on = [
    confluent_flink_statement.create-table-customers_keyed,
  ]
}

resource "confluent_flink_statement" "create-table-products_keyed" {
  organization {
    id = data.confluent_organization.main.id
  }

  environment {
    id = confluent_environment.shoe-env.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }

  principal {
    id = confluent_service_account.shoe-statements-runner.id
  }
  statement  = "CREATE TABLE shoe_products_keyed(product_id STRING, brand STRING, `model` STRING, sale_price INT, rating DOUBLE, PRIMARY KEY (product_id) NOT ENFORCED) DISTRIBUTED INTO 1 BUCKETS;"
  properties = {
    "sql.current-catalog"  = confluent_environment.shoe-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.app-shoe-manager-flink-api-key.id
    secret = confluent_api_key.app-shoe-manager-flink-api-key.secret
  }
  depends_on = [
    confluent_flink_compute_pool.main,
    confluent_connector.source_shoe_products,
    confluent_connector.source_shoe_customers,
    confluent_connector.source_shoe_orders,
  ]
}

resource "confluent_flink_statement" "insert-into-products_keyed" {
  organization {
    id = data.confluent_organization.main.id
  }

  environment {
    id = confluent_environment.shoe-env.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }

  principal {
    id = confluent_service_account.shoe-statements-runner.id
  }
  statement  = "INSERT INTO shoe_products_keyed SELECT id, brand, `name`, sale_price, rating FROM shoe_products;"
  properties = {
    "sql.current-catalog"  = confluent_environment.shoe-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.app-shoe-manager-flink-api-key.id
    secret = confluent_api_key.app-shoe-manager-flink-api-key.secret
  }
  depends_on = [
    confluent_flink_statement.create-table-products_keyed,
  ]
}

resource "confluent_flink_statement" "create-table-enriched" {
  organization {
    id = data.confluent_organization.main.id
  }

  environment {
    id = confluent_environment.shoe-env.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }

  principal {
    id = confluent_service_account.shoe-statements-runner.id
  }
  statement  = "CREATE TABLE shoe_orders_enriched(order_id INT, first_name STRING, last_name STRING, email STRING, brand STRING, `model` STRING, sale_price INT, rating DOUBLE) DISTRIBUTED INTO 1 BUCKETS WITH ('changelog.mode' = 'retract');"
  properties = {
    "sql.current-catalog"  = confluent_environment.shoe-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.app-shoe-manager-flink-api-key.id
    secret = confluent_api_key.app-shoe-manager-flink-api-key.secret
  }
  depends_on = [
    confluent_flink_statement.insert-into-customers_keyed,
    confluent_flink_statement.insert-into-products_keyed,
  ]
}

resource "confluent_flink_statement" "insert-into-enriched" {
  organization {
    id = data.confluent_organization.main.id
  }

  environment {
    id = confluent_environment.shoe-env.id
  }

  compute_pool {
    id = confluent_flink_compute_pool.main.id
  }

  principal {
    id = confluent_service_account.shoe-statements-runner.id
  }
  statement  = "INSERT INTO shoe_orders_enriched(order_id, first_name, last_name, email, brand, `model`, sale_price, rating) SELECT so.order_id, sc.first_name, sc.last_name, sc.email, sp.brand, sp.`model`, sp.sale_price, sp.rating FROM shoe_orders so INNER JOIN shoe_customers_keyed sc  ON so.customer_id = sc.customer_id INNER JOIN shoe_products_keyed sp ON so.product_id = sp.product_id;"
  properties = {
    "sql.current-catalog"  = confluent_environment.shoe-env.display_name
    "sql.current-database" = confluent_kafka_cluster.basic.display_name
  }
  rest_endpoint = data.confluent_flink_region.region.rest_endpoint

  credentials {
    key    = confluent_api_key.app-shoe-manager-flink-api-key.id
    secret = confluent_api_key.app-shoe-manager-flink-api-key.secret
  }
  depends_on = [
    confluent_flink_statement.create-table-enriched,
  ]
}
