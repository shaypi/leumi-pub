pipeline {
    agent {
        docker { image 'custom-jenkins-docker:latest'}
    }
    environment {
        AWS_REGION = 'eu-west-1'
        AWS_ACCESS_KEY_ID = credentials('aws-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-key')
    }

    options {
            disableConcurrentBuilds()
            skipDefaultCheckout()
            timestamps()
    }

    parameters {
        choice(
            choices: ['apply', 'destroy'],
            description: 'Apply or Destroy',
            name: 'CONDITION',
        )
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    checkout([$class: 'GitSCM', 
                              branches: [[name: '*/main']], 
                              extensions: [[$class: 'CloneOption', depth: 1]], 
                              userRemoteConfigs: [[credentialsId: 'github', url: 'https://github.com/shaypi/leumi.git']]])
                }
            }
        }

        stage('Install third-party dependencies') {
            steps {
                sh 'apt-get update && apt-get install -y zip curl'
            }
        }

        stage('Install AWS CLI') {
            steps {
                sh 'curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"'
                sh 'unzip -o awscliv2.zip'
                sh './aws/install'
                sh 'apt-get update'
                sh 'apt-get dist-upgrade -y'
                sh 'apt-get install -y less'
            }
        }

        stage('Install Terraform') {
            steps {
                sh 'DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get -y install software-properties-common'
                sh 'apt-get update && apt-get install -y gnupg wget'
                sh 'wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg'
                sh 'gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint'
                sh 'echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list'
                sh 'apt update'
                sh 'apt-get -y install terraform'
                sh 'terraform --version'
            }
        }

        stage('Configure AWS credentials') {
            steps {
                sh 'mkdir ~/.aws'
                sh 'echo "[default]" > ~/.aws/credentials'
                sh 'echo "aws_access_key_id=${AWS_ACCESS_KEY_ID}" >> ~/.aws/credentials'
                sh 'echo "aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}" >> ~/.aws/credentials'
                sh 'echo "[default]" > ~/.aws/config'
                sh 'echo "region=${AWS_REGION}" >> ~/.aws/config'
            }
        }

        stage('Configure backend') {
            steps {
                dir('terraform/environments/leumi') {
                    sh '''
                        cat <<EOF > backend.conf
                        encrypt = true
                        bucket = "leumi-global-state"
                        key = "env/ecr/terraform.tfstate"
                        region = "${AWS_REGION}"
                        access_key = "${AWS_ACCESS_KEY_ID}"
                        secret_key = "${AWS_SECRET_ACCESS_KEY}"
                    '''
                }
            }
        }

        stage('Initialize Terraform') {
            steps {
                dir('terraform/environments/leumi') {
                    sh 'terraform init -backend-config=backend.conf'
                }
            }
        }

        // stage('debug') {
        //     steps {
        //         sh 'sleep 60000'
        //     }
        // }

        stage('Terraform Plan') {
            steps {
                dir('terraform/environments/leumi') {
                    sh '''
                        terraform validate
                        terraform fmt
                        terraform init -backend-config=backend.conf
                        terraform plan -var-file="main.tfvars"
                    '''
                }
            }
            post {
                always {
                    echo 'Terraform plan complete!'
                }
            }
        }

        stage('Terraform Apply/Destroy') {
            steps {
                dir('terraform/environments/leumi') {
                    sh '''
                        terraform validate
                        terraform fmt
                        terraform init -backend-config=backend.conf
                        terraform apply -var-file="main.tfvars" -auto-approve
                    '''
                }
            }
            post {
                always {
                    echo 'Terraform apply/destroy complete!'
                }
            }
        }
    }
}