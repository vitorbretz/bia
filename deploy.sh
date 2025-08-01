#!/bin/bash

# Script de Deploy para ECS - Projeto BIA
# Autor: Amazon Q
# Versão: 1.0

set -e

# Configurações padrão
DEFAULT_REGION="us-east-1"
DEFAULT_CLUSTER="bia-cluster-alb"
DEFAULT_SERVICE="bia-service"
DEFAULT_TASK_FAMILY="bia-tf"
DEFAULT_ECR_REPO="bia-app"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir help
show_help() {
    cat << EOF
🚀 Script de Deploy ECS - Projeto BIA

USO:
    ./deploy.sh [COMANDO] [OPÇÕES]

COMANDOS:
    build       Faz build da imagem Docker com commit hash
    push        Faz push da imagem para ECR
    deploy      Faz deploy no ECS criando nova task definition
    rollback    Faz rollback para uma versão anterior
    list        Lista as últimas 10 versões disponíveis
    help        Exibe esta ajuda

OPÇÕES:
    -r, --region REGION         Região AWS (padrão: $DEFAULT_REGION)
    -c, --cluster CLUSTER       Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)
    -s, --service SERVICE       Nome do serviço ECS (padrão: $DEFAULT_SERVICE)
    -f, --family FAMILY         Família da task definition (padrão: $DEFAULT_TASK_FAMILY)
    -e, --ecr-repo REPO         Nome do repositório ECR (padrão: $DEFAULT_ECR_REPO)
    -t, --tag TAG               Tag específica para rollback
    -h, --help                  Exibe esta ajuda

EXEMPLOS:
    # Deploy completo (build + push + deploy)
    ./deploy.sh deploy

    # Build apenas
    ./deploy.sh build

    # Deploy em região específica
    ./deploy.sh deploy --region us-west-2

    # Rollback para versão específica
    ./deploy.sh rollback --tag abc1234

    # Listar versões disponíveis
    ./deploy.sh list

FLUXO DE DEPLOY:
    1. Build da imagem com tag do commit hash
    2. Push da imagem para ECR
    3. Criação de nova task definition
    4. Update do serviço ECS
    5. Aguarda deploy completar

ROLLBACK:
    O script mantém histórico de task definitions permitindo
    rollback rápido para qualquer versão anterior.

EOF
}

# Função para log colorido
log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $*" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" ;;
    esac
}

# Função para obter commit hash
get_commit_hash() {
    if git rev-parse --git-dir > /dev/null 2>&1; then
        git rev-parse --short=7 HEAD
    else
        log "ERROR" "Não é um repositório Git válido"
        exit 1
    fi
}

# Função para obter account ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text --region "$REGION"
}

# Função para fazer build da imagem
build_image() {
    local commit_hash=$(get_commit_hash)
    local account_id=$(get_account_id)
    local ecr_uri="${account_id}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"
    
    log "INFO" "Iniciando build da imagem..."
    log "INFO" "Commit hash: $commit_hash"
    log "INFO" "ECR URI: $ecr_uri"
    
    # Build da imagem
    docker build -t "${ECR_REPO}:${commit_hash}" .
    docker tag "${ECR_REPO}:${commit_hash}" "${ecr_uri}:${commit_hash}"
    docker tag "${ECR_REPO}:${commit_hash}" "${ecr_uri}:latest"
    
    log "SUCCESS" "Build concluído com sucesso!"
    echo "IMAGE_TAG=${commit_hash}" > .deploy_vars
    echo "ECR_URI=${ecr_uri}" >> .deploy_vars
}

# Função para fazer push para ECR
push_image() {
    if [[ ! -f .deploy_vars ]]; then
        log "ERROR" "Arquivo .deploy_vars não encontrado. Execute 'build' primeiro."
        exit 1
    fi
    
    source .deploy_vars
    
    log "INFO" "Fazendo login no ECR..."
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ECR_URI%/*}"
    
    log "INFO" "Fazendo push da imagem..."
    docker push "${ECR_URI}:${IMAGE_TAG}"
    docker push "${ECR_URI}:latest"
    
    log "SUCCESS" "Push concluído com sucesso!"
}

# Função para criar task definition
create_task_definition() {
    if [[ ! -f .deploy_vars ]]; then
        log "ERROR" "Arquivo .deploy_vars não encontrado. Execute 'build' primeiro."
        exit 1
    fi
    
    source .deploy_vars
    
    log "INFO" "Criando nova task definition..."
    
    # Obter task definition atual
    local current_td=$(aws ecs describe-task-definition \
        --task-definition "$TASK_FAMILY" \
        --region "$REGION" \
        --query 'taskDefinition' \
        --output json 2>/dev/null || echo "{}")
    
    if [[ "$current_td" == "{}" ]]; then
        log "WARN" "Task definition não encontrada. Criando nova..."
        create_new_task_definition
    else
        log "INFO" "Atualizando task definition existente..."
        update_task_definition "$current_td"
    fi
}

# Função para criar nova task definition
create_new_task_definition() {
    source .deploy_vars
    
    cat > task-definition.json << EOF
{
    "family": "$TASK_FAMILY",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["EC2"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": "arn:aws:iam::$(get_account_id):role/ecsTaskExecutionRole",
    "containerDefinitions": [
        {
            "name": "bia-container",
            "image": "${ECR_URI}:${IMAGE_TAG}",
            "portMappings": [
                {
                    "containerPort": 8080,
                    "protocol": "tcp"
                }
            ],
            "essential": true,
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/ecs/$TASK_FAMILY",
                    "awslogs-region": "$REGION",
                    "awslogs-stream-prefix": "ecs"
                }
            },
            "environment": [
                {
                    "name": "NODE_ENV",
                    "value": "production"
                }
            ]
        }
    ]
}
EOF

    register_task_definition
}

# Função para atualizar task definition existente
update_task_definition() {
    local current_td="$1"
    source .deploy_vars
    
    # Atualizar apenas a imagem na task definition
    echo "$current_td" | jq --arg image "${ECR_URI}:${IMAGE_TAG}" \
        'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy) | 
         .containerDefinitions[0].image = $image' > task-definition.json
    
    register_task_definition
}

# Função para registrar task definition
register_task_definition() {
    log "INFO" "Registrando nova task definition..."
    
    local new_td=$(aws ecs register-task-definition \
        --cli-input-json file://task-definition.json \
        --region "$REGION" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    log "SUCCESS" "Task definition criada: $new_td"
    echo "TASK_DEFINITION_ARN=${new_td}" >> .deploy_vars
    
    # Limpar arquivo temporário
    rm -f task-definition.json
}

# Função para fazer deploy no ECS
deploy_service() {
    if [[ ! -f .deploy_vars ]]; then
        log "ERROR" "Arquivo .deploy_vars não encontrado. Execute 'build' primeiro."
        exit 1
    fi
    
    source .deploy_vars
    
    log "INFO" "Atualizando serviço ECS..."
    
    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --task-definition "$TASK_DEFINITION_ARN" \
        --region "$REGION" \
        --query 'service.serviceName' \
        --output text > /dev/null
    
    log "SUCCESS" "Serviço atualizado com sucesso!"
    log "INFO" "Aguardando deploy completar..."
    
    # Aguardar deploy completar
    aws ecs wait services-stable \
        --cluster "$CLUSTER" \
        --services "$SERVICE" \
        --region "$REGION"
    
    log "SUCCESS" "Deploy concluído com sucesso!"
    log "INFO" "Versão deployada: ${IMAGE_TAG}"
}

# Função para listar versões
list_versions() {
    log "INFO" "Listando últimas 10 versões disponíveis..."
    
    aws ecs list-task-definitions \
        --family-prefix "$TASK_FAMILY" \
        --status ACTIVE \
        --sort DESC \
        --max-items 10 \
        --region "$REGION" \
        --query 'taskDefinitionArns[]' \
        --output table
}

# Função para rollback
rollback() {
    local target_tag="$1"
    
    if [[ -z "$target_tag" ]]; then
        log "ERROR" "Tag para rollback não especificada. Use --tag ou -t"
        exit 1
    fi
    
    log "INFO" "Iniciando rollback para versão: $target_tag"
    
    local account_id=$(get_account_id)
    local ecr_uri="${account_id}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"
    
    # Verificar se a imagem existe
    if ! aws ecr describe-images \
        --repository-name "$ECR_REPO" \
        --image-ids imageTag="$target_tag" \
        --region "$REGION" > /dev/null 2>&1; then
        log "ERROR" "Imagem com tag '$target_tag' não encontrada no ECR"
        exit 1
    fi
    
    # Criar task definition para rollback
    echo "IMAGE_TAG=${target_tag}" > .deploy_vars
    echo "ECR_URI=${ecr_uri}" >> .deploy_vars
    
    create_task_definition
    deploy_service
    
    log "SUCCESS" "Rollback concluído para versão: $target_tag"
}

# Função principal de deploy
full_deploy() {
    log "INFO" "Iniciando deploy completo..."
    build_image
    push_image
    create_task_definition
    deploy_service
    
    # Limpar arquivo temporário
    rm -f .deploy_vars
    
    log "SUCCESS" "Deploy completo finalizado!"
}

# Parse dos argumentos
REGION="$DEFAULT_REGION"
CLUSTER="$DEFAULT_CLUSTER"
SERVICE="$DEFAULT_SERVICE"
TASK_FAMILY="$DEFAULT_TASK_FAMILY"
ECR_REPO="$DEFAULT_ECR_REPO"
ROLLBACK_TAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER="$2"
            shift 2
            ;;
        -s|--service)
            SERVICE="$2"
            shift 2
            ;;
        -f|--family)
            TASK_FAMILY="$2"
            shift 2
            ;;
        -e|--ecr-repo)
            ECR_REPO="$2"
            shift 2
            ;;
        -t|--tag)
            ROLLBACK_TAG="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        build|push|deploy|rollback|list|help)
            COMMAND="$1"
            shift
            ;;
        *)
            log "ERROR" "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verificar se comando foi especificado
if [[ -z "${COMMAND:-}" ]]; then
    log "ERROR" "Comando não especificado"
    show_help
    exit 1
fi

# Executar comando
case "$COMMAND" in
    "build")
        build_image
        ;;
    "push")
        push_image
        ;;
    "deploy")
        full_deploy
        ;;
    "rollback")
        rollback "$ROLLBACK_TAG"
        ;;
    "list")
        list_versions
        ;;
    "help")
        show_help
        ;;
    *)
        log "ERROR" "Comando inválido: $COMMAND"
        show_help
        exit 1
        ;;
esac
