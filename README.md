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

Dois workflows em `.github/workflows/`:

| Workflow | Gatilho | O que faz |
|---|---|---|
| `pr.yml` | Todo Pull Request contra `main` | `fmt -check` → `init` → `validate` → `plan` (nunca aplica) |
| `deploy.yml` | Push/merge na `main`, ou manual (`workflow_dispatch`, aba Actions → Run workflow) | `fmt -check` → `init` → `validate` → `apply -auto-approve` |

O `apply` roda a cada merge na `main`, ou sob demanda pela aba Actions — mas só **funciona** se as credenciais AWS cadastradas nos Secrets ainda estiverem válidas (ver seção abaixo sobre AWS Academy Learner Lab). O gatilho manual existe justamente para reaplicar sem precisar de um commit novo quando só as credenciais expiraram.

### Configuração necessária no GitHub (Settings → Secrets and variables → Actions)

**Secrets** (dados sensíveis, criptografados):

| Nome | Descrição |
|---|---|
| `AWS_ACCESS_KEY_ID` | Access key da sessão do AWS Academy Learner Lab |
| `AWS_SECRET_ACCESS_KEY` | Secret key da sessão do AWS Academy Learner Lab |
| `AWS_SESSION_TOKEN` | Session token temporário (obrigatório no Learner Lab, além das duas chaves acima) |

**Variables** (texto simples, não sensível):

| Nome | Descrição | Exemplo |
|---|---|---|
| `TF_STATE_BUCKET` | Bucket S3 do state remoto | `fiap-soat-db-tfstate` |
| `TF_STATE_KEY` | Path do state dentro do bucket | `db/prod/terraform.tfstate` |
| `TF_STATE_REGION` | Região do bucket de state | `us-east-1` |
| `VPC_ID` | ID da VPC (vem do repositório de infraestrutura Kubernetes) | `vpc-0123456789abcdef0` |
| `SUBNET_IDS` | IDs das subnets, **em formato de lista JSON** (com colchetes e aspas duplas) | `["subnet-0abc123","subnet-0def456"]` |
| `ALLOWED_SG_ID` | ID do Security Group do cluster Kubernetes | `sg-0123456789abcdef0` |
| `DB_NAME` | Nome do banco de dados | `mecanica_db` |

> ⚠️ `SUBNET_IDS` precisa estar entre colchetes e aspas duplas (formato JSON), porque a variável correspondente no Terraform é `list(string)`. Uma string solta (`subnet-abc,subnet-def`) falha na conversão de tipo durante o `plan`/`apply`.

### ⚠️ AWS Academy Learner Lab — credenciais expiram

As credenciais do Learner Lab são temporárias e expiram poucas horas após o início da sessão (`Start Lab`). O workflow **não renova isso sozinho**. Sempre que for necessário rodar o pipeline com um `apply` de verdade (ex: antes de gravar o vídeo de demonstração):

1. Iniciar uma sessão nova no AWS Academy Learner Lab.
2. Copiar as credenciais temporárias exibidas (`AWS Details` → `AWS CLI`).
3. Atualizar os 3 Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) no GitHub com os novos valores.
4. Só então mergear o PR (ou fazer um novo commit em `main`) para disparar o `deploy.yml`.

Se o merge acontecer com a sessão expirada, o step `Terraform apply` falha com erro de credencial/token expirado — não é um bug do código, é a natureza das credenciais temporárias do Learner Lab.

### Branch protection

A branch `main` deve estar protegida (Settings → Branches → Branch protection rule), exigindo:
- Pull Request obrigatório antes de mergear (nenhum push direto na `main`);
- O status check do `pr.yml` passando (`fmt`, `validate` e `plan` sem erro) antes de permitir o merge.

## Licença

Ver [LICENSE](./LICENSE).

## Documentação

As decisões deste repositório estão em [`docs/`](docs/README.md):

- [RFC-001](docs/rfc/RFC-001-rds-postgresql-learner-lab.md) — RDS PostgreSQL no AWS Academy Learner Lab: restrições, alternativas, custo e validação
- [ADR-001](docs/adr/ADR-001-postgresql-rds-gerenciado.md) — PostgreSQL gerenciado no RDS, fora do cluster
- [ADR-002](docs/adr/ADR-002-credenciais-secrets-manager.md) — credenciais geradas pelo Terraform e entregues pelo Secrets Manager
- [ADR-003](docs/adr/ADR-003-rede-desacoplada-sg.md) — rede recebida do repositório Kubernetes e acesso restrito por Security Group
- [ADR-004](docs/adr/ADR-004-state-s3-ambiente-unico.md) — state remoto em S3 e ambiente único de produção
