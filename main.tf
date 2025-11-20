# VPC
resource "aws_vpc" "myVpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "my-vpc"
  }
}

# Public Subnet
resource "aws_subnet" "public-subnet" {
  vpc_id                  = aws_vpc.myVpc.id
  availability_zone       = var.availability_zone
  cidr_block              = var.subnet_cidr_block
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "myIGW" {
  vpc_id = aws_vpc.myVpc.id
  tags = {
    Name = "myIGW"
  }
}

# Route Table
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.myVpc.id
  tags = {
    Name = "public-rt"
  }
}

# Route
resource "aws_route" "default-route" {
  route_table_id         = aws_route_table.public-rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.myIGW.id
}

# Route Table Association
resource "aws_route_table_association" "public-rt-associaction" {
  route_table_id = aws_route_table.public-rt.id
  subnet_id      = aws_subnet.public-subnet.id
}

# Security Group
resource "aws_security_group" "web-sg" {
  name        = "my-web-sg"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.myVpc.id
  ingress {
    from_port   = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    to_port     = 80
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "my-web-sg"
  }
}

# EC2 Instance
resource "aws_instance" "web-server" {
  ami                         = var.ec2_ami
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.public-subnet.id
  vpc_security_group_ids      = [aws_security_group.web-sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  key_name                    = var.ec2_keyName
  associate_public_ip_address = true
  tags = {
    Name = "web-server"
  }

  user_data = <<-EOF
              #!bin/bash
              yum update -y
              dnf install nginx -y
              systemctl start nginx
              systemctl enable nginx
              
              cat > /usr/share/nginx/html/index.html << 'HTML'
              <!DOCTYPE html>
              <html>
              <head>
                  <title>EC2 - Splunk</title>
              </head>
              <body>
              <h2>Submit the Form</h2>
                <form method="POST" action="/form-submit">
                  <label>Message:</label>
                  <input type="text" name="msg" required />
                  <br><br>
                  <button type="submit">Submit</button>
                </form>
              </body>
              HTML

              cat > /usr/share/nginx/html/submit-success.html << 'HTML'
              <!DOCTYPE html>
              <html>
              <head>
                  <title>Submission Successful</title>
              </head>
              <body>
                  <h2>Your message has been submitted successfully!</h2>
              </body>
              HTML

              cat > /etc/nginx/conf.d/form-submit.conf << 'NGINXCONF'
              server {
                listen 80;
                server_name _;

                root /usr/share/nginx/html;

              location /form-submit {
                if ($request_method = POST) {
                    return 307 /submit-success.html;
                }
              }


                location / {
                  try_files $uri $uri/ =404;
                }
              }
              NGINXCONF

              systemctl restart nginx

              yum install amazon-cloudwatch-agent -y

              cat > /opt/aws/amazon-cloudwatch-agent/etc/nginx-cw.json << 'CW'
              {
                  "logs": {
                    "logs_collected": {
                      "files": {
                        "collect_list": [
                          {
                            "file_path": "/var/log/nginx/access.log",
                            "log_group_name": "nginx-logs",
                            "log_stream_name": "{instance_id}-access"
                          },
                          {
                            "file_path": "/var/log/nginx/error.log",
                            "log_group_name": "nginx-logs",
                            "log_stream_name": "{instance_id}-error"
                          }
                        ]
                      }
                    }
                  }
              }
              CW

               /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/nginx-cw.json -s



  EOF
}

# IAM Role for ec2
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy Attachment
resource "aws_iam_role_policy_attachment" "cloudwatchAgent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# IAM role for lambda function
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy
resource "aws_iam_role_policy" "name" {
  name = "lambda-cloud-policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

}

# IAM Policy Attachment for lambda
resource "aws_iam_role_policy_attachment" "lambdaexecution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# CloudWatch Log Group

resource "aws_cloudwatch_log_group" "nginx-logs" {
  name              = "nginx-logs"
  retention_in_days = 30
}

# lambda function
resource "aws_lambda_function" "lambda-splunk" {
  function_name = "my-lambda-splunk"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  filename      = data.archive_file.name.output_path
  environment {
    variables = {
      SPLUNK_HEC_URL   = var.splunk_url
      SPLUNK_HEC_TOKEN = var.splunk_token
    }
  }
}

# Data Source for lambda

data "archive_file" "name" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda.py"
  output_path = "${path.module}/lambda.zip"
}


# Subscription Filter
resource "aws_cloudwatch_log_subscription_filter" "name" {
  name            = "lambda-to-splunk"
  log_group_name  = aws_cloudwatch_log_group.nginx-logs.name
  filter_pattern  = ""
  destination_arn = aws_lambda_function.lambda-splunk.arn
  depends_on      = [aws_lambda_permission.allow_cloudwatch]
}

# Lambda Permission to allow CloudWatch to invoke it
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda-splunk.function_name
  principal     = "logs.us-east-1.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.nginx-logs.arn}:*"
}
