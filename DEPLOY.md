# 🚀 Script de Deploy ECS - Projeto BIA

Este script automatiza o processo de deploy da aplicação BIA no Amazon ECS, incluindo funcionalidades de rollback baseadas em commit hash.

## 📋 Pré-requisitos

- AWS CLI configurado com credenciais válidas
- Docker instalado e rodando
- Git (para obter commit hash)
- Repositório ECR criado
- Cluster ECS configurado
- jq instalado (para manipulação JSON)

## 🔧 Configuração Inicial

### 1. Variáveis de Ambiente (Opcional)
Você pode definir as seguintes variáveis para personalizar o comportamento:

```bash
export AWS_DEFAULT_REGION=us-east-1
export ECS_CLUSTER=bia-cluster-alb
export ECS_SERVICE=bia-service
export TASK_FAMILY=bia-tf
export ECR_REPO=bia-app
```

### 2. Permissões IAM Necessárias
O usuário/role deve ter as seguintes permissões:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeImages",
                "ecs:RegisterTaskDefinition",
                "ecs:UpdateService",
                "ecs:DescribeTaskDefinition",
                "ecs:ListTaskDefinitions",
                "ecs:DescribeServices",
                "sts:GetCallerIdentity",
                "logs:CreateLogGroup",
                "iam:PassRole"
            ],
            "Resource": "*"
        }
    ]
}
```

## 🚀 Uso do Script

### Deploy Completo
```bash
# Deploy completo (build + push + deploy)
./deploy.sh deploy

# Deploy em região específica
./deploy.sh deploy --region us-west-2

# Deploy com configurações customizadas
./deploy.sh deploy --cluster meu-cluster --service meu-service
```

### Comandos Individuais
```bash
# Apenas build da imagem
./deploy.sh build

# Apenas push para ECR (após build)
./deploy.sh push

# Listar versões disponíveis
./deploy.sh list
```

### Rollback
```bash
# Rollback para versão específica
./deploy.sh rollback --tag abc1234

# Listar versões para escolher rollback
./deploy.sh list
./deploy.sh rollback --tag def5678
```

## 📊 Fluxo de Deploy

1. **Build**: Cria imagem Docker com tag baseada no commit hash
2. **Push**: Envia imagem para ECR
3. **Task Definition**: Cria nova task definition apontando para a imagem
4. **Deploy**: Atualiza serviço ECS
5. **Verificação**: Aguarda deploy completar

## 🔄 Sistema de Versionamento

- **Tag da Imagem**: Baseada nos últimos 7 caracteres do commit hash
- **Task Definition**: Nova revisão criada para cada deploy
- **Rollback**: Utiliza imagens já existentes no ECR

### Exemplo de Tags
```
Commit: a1b2c3d4e5f6g7h8
Tag da Imagem: a1b2c3d
ECR URI: 123456789.dkr.ecr.us-east-1.amazonaws.com/bia-app:a1b2c3d
```

## 🛠️ Troubleshooting

### Erro: "Não é um repositório Git válido"
```bash
# Inicializar repositório Git se necessário
git init
git add .
git commit -m "Initial commit"
```

### Erro: "ECR repository does not exist"
```bash
# Criar repositório ECR
aws ecr create-repository --repository-name bia-app --region us-east-1
```

### Erro: "Task definition not found"
O script criará automaticamente uma nova task definition se não existir.

### Erro: "Service not found"
```bash
# Verificar se o serviço existe
aws ecs describe-services --cluster bia-cluster-alb --services bia-service
```

## 📝 Logs e Monitoramento

- **CloudWatch Logs**: `/ecs/bia-tf`
- **Deploy Status**: O script aguarda o deploy completar
- **Rollback**: Processo rápido usando imagens já existentes

## 🔒 Segurança

- Credenciais AWS obtidas via AWS CLI
- Imagens taggeadas com commit específico
- Task definitions versionadas
- Rollback seguro para versões testadas

## 📈 Boas Práticas

1. **Sempre teste** em ambiente de desenvolvimento primeiro
2. **Mantenha backup** das task definitions importantes
3. **Use tags descritivas** nos commits para facilitar identificação
4. **Monitore logs** após deploy
5. **Teste rollback** em ambiente não-produtivo

## 🆘 Suporte

Para ajuda adicional:
```bash
./deploy.sh help
```

Ou consulte a documentação do projeto BIA.
