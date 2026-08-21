# EC2 IAM Role
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "ec2_policy" {
  name = "${var.project_name}-ec2-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy_attachment" "ec2_policy_attachment" {
  name       = "${var.project_name}-ec2-policy-attachment"
  policy_arn = aws_iam_policy.ec2_policy.arn
  roles      = [aws_iam_role.ec2_role.name]
}

# Lets us inspect/debug the instance via SSM Session Manager instead of
# needing a SSH key pair or opening port 22 further.
resource "aws_iam_policy_attachment" "ec2_ssm_access" {
  name       = "${var.project_name}-ec2-ssm-access"
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  roles      = [aws_iam_role.ec2_role.name]
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance
resource "aws_instance" "processor" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids      = [var.security_group_id]

  # cloud-init only ever runs user_data on an instance's first boot, so a
  # plain edit to this script wouldn't otherwise reach an already-running
  # instance. This forces a fresh instance (fresh boot, fresh cloud-init run)
  # whenever user_data.sh changes, so script fixes actually take effect via
  # `terraform apply` instead of needing a manual SSM patch.
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user_data.sh", {
    sqs_queue_url        = var.sqs_queue_url
    source_bucket_name   = var.source_bucket_name
    target_bucket_name   = var.target_bucket_name
    aws_region          = var.aws_region
  })

  tags = {
    Name = "${var.project_name}-processor"
  }
}