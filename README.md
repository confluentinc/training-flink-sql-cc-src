# Mastering Flink SQL on Confluent Cloud

This is the source code accompanying the **Mastering Flink SQL on Confluent Cloud** course.

## Terraform Labs

Each lab provisions its own Confluent Cloud environment with Kafka clusters, topics, and connectors via Terraform.

| # | Lab | Focus |
|---|-----|-------|
| 3 | `lab-tables` | Creating and managing Flink SQL tables |
| 4 | `lab-time` | Time-based processing with clickstream data |
| 5 | `lab-aggregations` | Aggregations, keyed tables, and enriched joins |
| 6 | `lab-joins` | Joins, compact topics, and watermarks |
| 7 | `lab-patterns` | Pattern matching with stock trade data |
| 8 | `lab-udf` | User-defined functions (UDFs) |
| 9 | `lab-advanced` | Advanced Flink SQL techniques |

## Java UDFs

The `java/` directory contains Maven projects for custom Flink UDFs:

- **`lab-udf`** — `MaskCardNumber` UDF that masks credit card numbers (last 4 digits visible).
- **`lab-udf-v2`** — Enhanced version supporting `partial` and `full` masking modes.

Both target Java 17 and Flink 1.20.0, and use the Maven Shade plugin for packaging.

## Getting Started

Each Terraform lab follows the same layout:

```
terraform/lab-<name>/
├── main.tf
├── variables.tf
├── outputs.tf
└── terraform.tfvars
```

Set your Confluent Cloud API credentials before running Terraform:

```bash
source terraform/export-api-key.sh
```
