# fiap-soat-mecanica-api-db

Infraestrutura como código (Terraform) responsável por provisionar o banco de dados gerenciado (Amazon RDS PostgreSQL) utilizado pela aplicação **fiap-soat-mecanica-api**.

Este repositório é um dos 4 que compõem a arquitetura do Tech Challenge — Fase 3 (Pós-Graduação em Arquitetura de Software, FIAP):

| # | Repositório | Responsabilidade |
|---|---|---|
| 1 | Function de autenticação (serverless) | Valida CPF, consulta cliente e gera JWT |
| 2 | Infraestrutura Kubernetes | Provisiona o cluster (Terraform) |
| 3 | **fiap-soat-mecanica-api-db** (este repo) | Provisiona o banco de dados gerenciado (Terraform) |
| 4 | Aplicação principal | API rodando no Kubernetes |

> Este repositório cuida **apenas** da infraestrutura de banco de dados — não contém aplicação, não possui Dockerfile.

## Arquitetura

```
                         ┌─────────────────────────────┐
                         │   VPC (criada no repo de     │
                         │   infraestrutura Kubernetes) │
                         │                               │
                         │  ┌────────────┐   ingress:5432 (origem: SG do EKS)
                         │  │  Cluster    │─────────────┐ │
                         │  │  Kubernetes │             ▼ │
                         │  └────────────┘   ┌──────────────────────┐
                         │                    │ Security Group (RDS) │
                         │                    └──────────┬───────────┘
                         │                               │
                         │                    ┌──────────▼───────────┐
                         │                    │   Amazon RDS          │
                         │                    │   (PostgreSQL)        │
                         │                    └──────────┬───────────┘
                         └───────────────────────────────┼─────────────┘
                                                          │
                                              senha gerada via random_password
                                                          │
                                              ┌───────────▼────────────┐
                                              │  AWS Secrets Manager   │
                                              │  (credenciais do DB)   │
                                              └────────────────────────┘
                                                          ▲
                                                          │ lê credenciais
                                              ┌───────────┴────────────┐
                                              │  Aplicação (repo 4)     │
                                              └─────────────────────────┘
```

*(diagrama de componentes/sequência detalhado a ser adicionado na documentação final do projeto — RFC/ADR)*

## Decisões de arquitetura

- **VPC/subnets não são criadas neste repositório.** São recebidas como variáveis de entrada (`vpc_id`, `subnet_ids`), desacopladas do repositório que provisiona o cluster Kubernetes. Isso evita acoplamento entre os dois repositórios e permite trocar o provedor de rede sem alterar este código.
- **Nenhuma senha é hardcoded.** A senha do banco é gerada dinamicamente via `random_password` e armazenada no **AWS Secrets Manager** — nunca em GitHub Secrets, nunca em código versionado, nunca em variável de output.
- **Acesso de rede restrito.** O Security Group do RDS libera a porta `5432` **exclusivamente** para o Security Group informado via `allowed_security_group_id` (o cluster Kubernetes) — nunca `0.0.0.0/0`, e o RDS não é publicamente acessível (`publicly_accessible = false`).
- **State remoto em S3, sem DynamoDB.** O locking é feito nativamente pelo backend S3 (`use_lockfile = true`), disponível a partir do Terraform >= 1.10 — dispensando uma tabela DynamoDB adicional.
- **Backend parametrizado externamente.** O bloco `backend "s3" {}` não aceita variáveis do Terraform, então os valores reais (bucket, key, region) são passados via `-backend-config=backend.hcl` no `terraform init`. O arquivo `backend.hcl` real nunca é versionado (está no `.gitignore`) — apenas o `backend.hcl.example`, como template.
- **Apenas ambiente de produção.** Sem homologação separada neste momento. A estrutura de variáveis e do backend já reserva espaço para múltiplos ambientes no futuro (ex: `key = "db/<ambiente>/terraform.tfstate"`) sem exigir refatoração do módulo raiz.

## Pré-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.14.5, < 1.16.0`
- Credenciais AWS válidas configuradas no ambiente (via variáveis de ambiente, ou as credenciais temporárias fornecidas pelo AWS Academy Learner Lab)
- Um bucket S3 já existente para armazenar o state remoto

## Como usar

### 1. Configurar o backend

```bash
cp backend.hcl.example backend.hcl
```

Edite `backend.hcl` com os valores reais do bucket, key e região do seu ambiente. Esse arquivo **não deve ser commitado**.

### 2. Inicializar

```bash
terraform init -backend-config=backend.hcl
```

### 3. Planejar e aplicar

```bash
terraform plan  -var="vpc_id=<vpc-id>" -var="subnet_ids=[\"subnet-a\",\"subnet-b\"]" -var="allowed_security_group_id=<sg-id>" -var="db_name=<nome-do-banco>"
terraform apply -var="vpc_id=<vpc-id>" -var="subnet_ids=[\"subnet-a\",\"subnet-b\"]" -var="allowed_security_group_id=<sg-id>" -var="db_name=<nome-do-banco>"
```

> Na prática, recomenda-se criar um arquivo `terraform.tfvars` (ignorado pelo Git) com esses valores, em vez de passá-los na linha de comando.

## Variáveis

| Nome | Tipo | Obrigatória | Default | Descrição |
|---|---|---|---|---|
| `vpc_id` | `string` | Sim | — | ID da VPC onde o RDS será provisionado |
| `subnet_ids` | `list(string)` | Sim | — | IDs das subnets para o DB Subnet Group |
| `allowed_security_group_id` | `string` | Sim | — | ID do Security Group (cluster Kubernetes) autorizado a acessar o banco |
| `db_name` | `string` | Sim | — | Nome do banco de dados |
| `db_username` | `string` | Não | `postgres` | Usuário master do banco |
| `db_port` | `number` | Não | `5432` | Porta do banco |
| `db_engine_version` | `string` | Não | `16.1` | Versão do engine PostgreSQL |
| `db_instance_class` | `string` | Não | `db.t3.micro` | Classe de instância do RDS |
| `db_allocated_storage` | `number` | Não | `10` | Armazenamento alocado, em GB |
| `publicly_accessible` | `bool` | Não | `false` | Se o RDS deve ter endereço público — deve ser `false` |
| `skip_final_snapshot` | `bool` | Não | `true` | Se deve pular a criação de snapshot final ao dropar o RDS |
| `multi_az` | `bool` | Não | `false` | Se o RDS deve criar réplica na mesma região, em outra AZ |

## Outputs

| Nome | Descrição |
|---|---|
| `db_endpoint` | Endpoint (`host:porta`) do RDS para a aplicação se conectar |
| `db_secret_arn` | ARN do secret no Secrets Manager com as credenciais do banco |

A aplicação (repositório 4) consome `db_secret_arn` para ler usuário, senha, host e porta diretamente do AWS Secrets Manager em tempo de execução — a senha nunca trafega por este repositório além do próprio Terraform state.

## CI/CD

Pipeline de `validate` / `plan` / `apply` — ver `.github/workflows/`. *(a ser adicionado)*

## Licença

Ver [LICENSE](./LICENSE).
