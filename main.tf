# Provider Configuration
provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "lamar_main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "lamar-main-vpc"
  }
}

# Subnets
resource "aws_subnet" "lamar_public_subnet" {
  vpc_id                  = aws_vpc.lamar_main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "lamar-public-subnet"
  }
}

resource "aws_subnet" "lamar_private_subnet" {
  vpc_id            = aws_vpc.lamar_main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "lamar-private-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "lamar_main" {
  vpc_id = aws_vpc.lamar_main.id
  tags = {
    Name = "lamar-main-igw"
  }
}

# Route Table for Public Subnet
resource "aws_route_table" "lamar_public_rt" {
  vpc_id = aws_vpc.lamar_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lamar_main.id
  }

  tags = {
    Name = "lamar-public-rt"
  }
}

resource "aws_route_table_association" "lamar_public_subnet_association" {
  subnet_id      = aws_subnet.lamar_public_subnet.id
  route_table_id = aws_route_table.lamar_public_rt.id
}

# Security Groups
resource "aws_security_group" "lamar_mysql_sg" {
  vpc_id = aws_vpc.lamar_main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.lamar_wordpress_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lamar-mysql-sg"
  }
}

resource "aws_security_group" "lamar_wordpress_sg" {
  vpc_id = aws_vpc.lamar_main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    Name = "lamar-wordpress-sg"
  }
}

# MySQL Instance
resource "aws_instance" "lamar_mysql_instance" {
  ami           = "ami-0e2c8caa4b6378d8c" # Replace with a valid Ubuntu AMI ID
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.lamar_private_subnet.id
  security_groups = [aws_security_group.lamar_mysql_sg.id]
  key_name        = "lamar_tf_KP"

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install -y mysql-server
              sudo sed -i "s/bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
              sudo systemctl restart mysql
              sudo mysql -e "CREATE DATABASE wordpress_db;"
              sudo mysql -e "CREATE USER 'wp_user'@'%' IDENTIFIED BY 'secure_password';"
              sudo mysql -e "GRANT ALL PRIVILEGES ON wordpress_db.* TO 'wp_user'@'%';"
              sudo mysql -e "FLUSH PRIVILEGES;"
              echo "MySQL setup completed successfully" > /tmp/mysql_setup.log
            EOF

  tags = {
    Name = "lamar-mysql-instance"
  }
}

# WordPress Instance
resource "aws_instance" "lamar_wordpress_instance" {
  ami           = "ami-0e2c8caa4b6378d8c" # Replace with a valid Ubuntu AMI ID
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.lamar_public_subnet.id
  security_groups = [aws_security_group.lamar_wordpress_sg.id]
  key_name        = "lamar_tf_KP"

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install -y apache2 php php-mysql wget
              wget https://wordpress.org/latest.tar.gz
              tar -xvzf latest.tar.gz
              sudo mv wordpress /var/www/html/
              sudo chown -R www-data:www-data /var/www/html/wordpress
              sudo chmod -R 755 /var/www/html/wordpress
              sudo rm /var/www/html/index.html
              sudo systemctl restart apache2
              
              # Configure WordPress to connect to MySQL
              wp_config_file="/var/www/html/wordpress/wp-config.php"
              cp /var/www/html/wordpress/wp-config-sample.php $wp_config_file
              sed -i "s/database_name_here/wordpress_db/" $wp_config_file
              sed -i "s/username_here/wp_user/" $wp_config_file
              sed -i "s/password_here/secure_password/" $wp_config_file
              sed -i "s/localhost/${aws_instance.lamar_mysql_instance.private_ip}/" $wp_config_file
              
              echo "WordPress setup completed successfully" > /tmp/wordpress_setup.log
            EOF

  tags = {
    Name = "lamar-wordpress-instance"
  }
}

# Output EC2 instance public IP
output "lamar_public_ip" {
  value = aws_instance.lamar_wordpress_instance.public_ip
}




