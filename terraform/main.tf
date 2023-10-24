provider "aws" {
  region = "us-east-1"
}

# Create an S3 bucket
resource "aws_s3_bucket" "json-blob-demo-bucket" {
  bucket = "json-blob-demo-bucket"
}

# zip python code



data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "../.aws-sam/build/jsonprocessorfunction"
  output_path = "lambda_package.zip"

}

data "aws_iam_policy_document" "kinesis_firehose_stream_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "demo-json-blobparsing-firehose-role" {
  name               = "demo-json-blobparsing-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.kinesis_firehose_stream_assume_role.json
}


resource "aws_iam_policy" "demo-json-blob-parsing_policy" {
  name   = "demo-json-blob-parsing_policy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:*",
                "s3-object-lambda:*",
                "firehose:*",
                "glue:*",
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:ListAllMyBuckets",
                "s3:GetBucketAcl",
                "ec2:DescribeVpcEndpoints",
                "ec2:DescribeRouteTables",
                "ec2:CreateNetworkInterface",
                "ec2:DeleteNetworkInterface",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcAttribute",
                "iam:ListRolePolicies",
                "iam:GetRole",
                "iam:GetRolePolicy",
                "cloudwatch:PutMetricData"
              ],
            "Resource": [
                "*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:*:*:/aws-glue/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DeleteTags"
            ],
            "Condition": {
                "ForAllValues:StringEquals": {
                    "aws:TagKeys": [
                        "aws-glue-service-resource"
                    ]
                }
            },
            "Resource": [
                "arn:aws:ec2:*:*:network-interface/*",
                "arn:aws:ec2:*:*:security-group/*",
                "arn:aws:ec2:*:*:instance/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "demo-json-parsing-firehose-policy" {
  role       = aws_iam_role.demo-json-blobparsing-firehose-role.name
  policy_arn = aws_iam_policy.demo-json-blob-parsing_policy.arn
}




# # Create the Lambda function
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "batchoperations.s3.amazonaws.com"]
    }
  }
}


resource "aws_iam_role" "demo-json-blob-lambda-role" {
  name               = "demo-json-blob-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_policy" "demo-json-blob-lambda_policy" {
  name   = "demo-json-blob-lambda_policy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:*",
                "s3-object-lambda:*",
                "firehose:*",
                "lambda:*",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "sns:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "analytics-prodtest-blob-parse-lambda-policy" {
  role       = aws_iam_role.demo-json-blob-lambda-role.name
  policy_arn = aws_iam_policy.demo-json-blob-lambda_policy.arn
}


resource "aws_lambda_function" "blob-parser-lambda" {
  function_name    = "demo-blob-parser-lambda"
  role             = "${aws_iam_role.demo-json-blob-lambda-role.arn}"
  handler          = "app.lambda_handler"
  runtime          = "python3.9"
  timeout          = 180
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_package.output_path)
  
}


resource "aws_lambda_function" "blob-parser-lambda-batch" {
  function_name    = "demo-blob-parser-lambda-batchs"
  role             = "${aws_iam_role.demo-json-blob-lambda-role.arn}"
  handler          = "appbatch.lambda_handler"
  runtime          = "python3.9"
  timeout          = 300
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_package.output_path)
  
}

resource "aws_lambda_permission" "json-uploaded-trigger-permission" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.blob-parser-lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::json-blob-demo-bucket"
}

resource "aws_s3_bucket_notification" "json-uploaded-notification" {
  bucket = "json-blob-demo-bucket"
  lambda_function {
    lambda_function_arn = aws_lambda_function.blob-parser-lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json"
  }
  depends_on = [aws_lambda_permission.json-uploaded-trigger-permission]
}


#Glue
resource "aws_glue_catalog_database" "demo-json-blob-file-db" {
  name = "demo-json-blob-file-db"
}

resource "aws_glue_catalog_table" "demo-json-blob-file-table" {
  name          = "demo-json-blob-file-table"
  database_name = aws_glue_catalog_database.demo-json-blob-file-db.name

  storage_descriptor {
    location      = "s3://json-blob-demo-bucket/firehose/demojson"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = 1
      }
    }

    columns {
      name = "eventType"
      type = "string"
    }
    columns {
      name = "number"
      type = "int"
    }
    columns {
      name = "startTime"
      type = "string"
    }
    columns {
      name = "endTime"
      type = "string"
    }
    columns {
      name = "duration"
      type = "bigint"
    }
      columns {
      name = "inspiratoryTime"
      type = "bigint"
    }
      columns {
      name = "Rate"
      type = "bigint"
    }
      columns {
      name = "maskLeakage"
      type = "int"
    }
  }
}
# Firehose
resource "aws_kinesis_firehose_delivery_stream" "demo-json-blob-ingestion-firehose" {
  name        = "demo-json-blob-ingestion-firehose"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.demo-json-blobparsing-firehose-role.arn
    bucket_arn          = "arn:aws:s3:::json-blob-demo-bucket"
    prefix              = "firehose/demojson/yyyy=!{timestamp:yyyy}/mm=!{timestamp:MM}/dd=!{timestamp:dd}/"
    error_output_prefix = "firehose/demojson_errors/yyyy=!{timestamp:yyyy}/mm=!{timestamp:MM}/dd=!{timestamp:dd}/!{firehose:error-output-type}"
    buffer_interval     = 60
    buffer_size         = 128

    data_format_conversion_configuration {
      enabled = "true"

      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
          }
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {
          }
        }
      }

      schema_configuration {
        role_arn      = aws_iam_role.demo-json-blobparsing-firehose-role.arn
        database_name = aws_glue_catalog_table.demo-json-blob-file-table.database_name
        table_name    = aws_glue_catalog_table.demo-json-blob-file-table.name
        region        = "us-east-1"
      }
    }
  }
}