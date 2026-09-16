# RFC-001: Provisionamento do banco de dados gerenciado com Amazon RDS PostgreSQL no AWS Academy Learner Lab

- **Status:** Aprovado
- **Data:** 2026-09-15
- **Autora:** Karen Barcelos
- **Repositório:** fiap-soat-mecanica-api-db

## Resumo

Propõe-se provisionar o banco de dados da Mecânica do Braia como uma instância
**Amazon RDS PostgreSQL** gerenciada, via Terraform, dentro das restrições do
**AWS Academy Learner Lab**, na **mesma VPC do cluster Kubernetes** (repo #2),
com credenciais geradas em tempo de `apply` e entregues aos consumidores
exclusivamente pelo **AWS Secrets Manager**. Esta RFC registra as alternativas
avaliadas, as restrições que moldaram a solução, o contrato com os demais
repositórios e o custo estimado.

## Motivação

A Fase 3 exige um **banco de dados gerenciado** com justificativa da escolha
entre SQL e NoSQL, provisionado por Terraform, com pipeline de CI/CD e sem
credenciais em código. A aplicação principal (repo #4) já usa PostgreSQL desde
a Fase 1, com migrations versionadas junto do código, e a Function de
autenticação (repo #1) consulta a tabela `clientes` diretamente. Restava
definir **onde** e **como** esse banco passa a existir na nuvem, de forma
reproduzível em quatro contas diferentes durante o desenvolvimento e em uma
única conta na entrega.

## Restrições do Learner Lab que moldaram a proposta

| Restrição | Impacto |
| --- | --- |
| Não é possível criar IAM Roles, políticas ou OIDC providers | Sem role dedicada para o RDS; sem OIDC GitHub→AWS; a pipeline usa as credenciais temporárias da sessão |
| Credenciais temporárias (~4h): access key + secret + session token | Os três valores ficam em GitHub Secrets e precisam ser renovados antes de cada `apply` real |
| Crédito de ~US$ 50 por conta | Menor instância disponível, single-AZ, 10 GB; sem réplica, sem snapshot final |
| Recursos persistem após a sessão | Um RDS esquecido consome crédito; `apply_immediately` e `skip_final_snapshot` aceleram o ciclo destroy/apply |
| Região restrita (`us-east-1` / `us-west-2`) | Provider fixado em `us-east-1` |
| Quatro contas durante o desenvolvimento, uma na entrega | Nenhum account ID, ARN ou bucket fixo no código; tudo entra por variável ou `-backend-config` |
| Secrets Manager mantém secrets deletados por 7–30 dias por padrão | `recovery_window_in_days = 0` para permitir recriar `mecanica-db-credentials` no mesmo dia |

## Proposta

### 1. Instância RDS PostgreSQL single-AZ

- Identificador `mecanica-db-prod`, engine `postgres`, versão major `17`
  (variável `db_engine_version`; deixar apenas a major permite ao RDS escolher
  a minor mais recente disponível — a versão `17.1` foi rejeitada no primeiro
  `apply` e ajustada no PR #2).
- `db.t3.micro`, 10 GB de armazenamento, `multi_az = false`.
- `publicly_accessible = false` e `skip_final_snapshot = true`.
- `apply_immediately = true`: alterações não esperam a janela de manutenção,
  o que importa porque as sessões do Learner Lab duram poucas horas.
- Ver [ADR-001](../adr/ADR-001-postgresql-rds-gerenciado.md).

### 2. Rede recebida do repositório Kubernetes

- Este repositório **não cria** VPC nem subnets. Recebe `vpc_id`, `subnet_ids`
  e `allowed_security_group_id` como variáveis, preenchidas com os outputs
  `vpc_id`, `subnet_ids` e `cluster_security_group_id` do repo #2.
- Cria um `aws_db_subnet_group` (`mecanica-db-subnet-group`) e um
  `aws_security_group` (`mecanica-db-sg`) com ingress na porta `5432`
  **exclusivamente** a partir do Security Group do cluster.
- Ver [ADR-003](../adr/ADR-003-rede-desacoplada-sg.md).

### 3. Credenciais geradas e entregues pelo Secrets Manager

- `random_password` (16 caracteres, sem especiais) gera a senha master.
- `aws_secretsmanager_secret` `mecanica-db-credentials` guarda um JSON com
  `username`, `password`, `dbname`, `port` e `host`.
- Os outputs são apenas `db_endpoint` e `db_secret_arn`. A senha nunca sai como
  output, variável de pipeline ou arquivo versionado.
- Ver [ADR-002](../adr/ADR-002-credenciais-secrets-manager.md).

### 4. Terraform com backend S3 parametrizado por conta

- Bloco `backend "s3" { use_lockfile = true }` sem valores; `bucket`, `key` e
  `region` entram por `-backend-config` (arquivo `backend.hcl` local, ignorado
  pelo Git, ou variáveis `TF_STATE_*` na pipeline).
- Lock nativo do S3 (Terraform ≥ 1.10), dispensando DynamoDB.
- Terraform fixado em `>= 1.14.5, < 1.16.0`; providers `aws ~> 5.0` e
  `random ~> 3.6`, com `.terraform.lock.hcl` versionado.
- Ver [ADR-004](../adr/ADR-004-state-s3-ambiente-unico.md).

### 5. Pipeline (GitHub Actions)

| Workflow | Gatilho | Passos |
| --- | --- | --- |
| `pr.yml` | Pull Request para `main` | `fmt -check` → `init` → `validate` → `plan` |
| `deploy.yml` | Push em `main` ou `workflow_dispatch` | `fmt -check` → `init` → `validate` → `apply -auto-approve` |

O gatilho manual existe para reaplicar depois de renovar as credenciais do
Learner Lab sem precisar de um commit novo. As variáveis de entrada
(`VPC_ID`, `SUBNET_IDS`, `ALLOWED_SG_ID`, `DB_NAME`) são *Variables* do
repositório; os três valores da sessão AWS são *Secrets*.

## Contrato com os demais repositórios

| Repositório | O que consome deste | O que este consome dele |
| --- | --- | --- |
| #2 Kubernetes (`fiap-soat-mecanica-api-k8s`) | — | Outputs `vpc_id`, `subnet_ids`, `cluster_security_group_id` |
| #4 Aplicação (`fiap-soat-mecanica-api`) | `db_secret_arn` (lê host, porta, usuário e senha em tempo de execução); executa as migrations do schema | — |
| #1 Autenticação (`fiap-soat-mecanica-api-auth`) | O mesmo secret `mecanica-db-credentials`; roda nas subnets da VPC e no Security Group que o RDS já autoriza | — |

Este repositório entrega um banco **vazio** com o nome `db_name`. Tabelas,
índices e dados iniciais são responsabilidade das migrations da aplicação.

## Alternativas avaliadas

### Modelo de dados e serviço

| Opção | Prós | Contras | Decisão |
| --- | --- | --- | --- |
| **RDS PostgreSQL** | Gerenciado; mesmo engine das Fases 1 e 2; migrations e consultas existentes reaproveitadas; backups e patches automáticos | Custo fixo por hora, mesmo ocioso | **Escolhido** |
| Aurora PostgreSQL | Alta disponibilidade e escala de leitura | Instância mínima bem mais cara; Serverless v2 tem custo mínimo por ACU e mais complexidade — sem ganho para a carga de demonstração | Rejeitado |
| PostgreSQL em pod no EKS (StatefulSet + EBS) | Zero custo além dos nodes | Não é "banco gerenciado"; backup, patch e failover ficariam manuais; concorre por recursos com a API nos `t3.medium` | Rejeitado |
| DynamoDB (NoSQL) | Sem servidor, custo por uso | O domínio é relacional (clientes, veículos, ordens de serviço, peças, orçamentos) com integridade referencial e consultas por junção; exigiria reescrever persistência e migrations | Rejeitado |

### Entrega de credenciais

| Opção | Decisão | Motivo |
| --- | --- | --- |
| **Secrets Manager + `random_password`** | **Escolhido** | Senha nunca passa por pessoas, GitHub ou output; consumidores leem pelo ARN |
| GitHub Secrets com senha definida à mão | Rejeitado | Senha conhecida por quem cadastrou; cópia em cada repositório consumidor |
| SSM Parameter Store (SecureString) | Rejeitado | Sem rotação nativa; Secrets Manager já era o destino esperado pelos repos #1 e #4 |
| Output `sensitive` do Terraform | Rejeitado | Ainda fica legível no state e em `terraform output`; acopla consumidores ao state deste repo |

### Rede

| Opção | Decisão | Motivo |
| --- | --- | --- |
| **VPC do cluster, recebida por variável** | **Escolhido** | Zero recursos de rede aqui; RDS e nodes na mesma VPC sem peering ou NAT |
| VPC dedicada ao banco + peering | Rejeitado | Mais recursos, mais custo, e o peering precisaria ser coordenado entre dois repositórios |
| `data "aws_vpc" { default = true }` neste repositório | Rejeitado | Funciona hoje (o repo #2 usa a VPC default), mas amarra este código a essa escolha; a variável mantém o contrato explícito |

### Backend de state

| Opção | Decisão | Motivo |
| --- | --- | --- |
| **S3 + lockfile nativo** | **Escolhido** | Um recurso só; funciona em qualquer conta; mesmo padrão do repo #2 |
| S3 + DynamoDB | Rejeitado | Recurso extra por conta sem ganho |
| State local | Rejeitado | Pipeline não teria acesso; sem lock |

## Custo estimado (us-east-1, on-demand)

| Item | Valor/h | Valor/dia (24h) |
| --- | --- | --- |
| RDS `db.t3.micro` PostgreSQL single-AZ | ~US$ 0,017 | ~US$ 0,41 |
| Armazenamento 10 GB (gp2, ~US$ 0,115/GB-mês) | ~US$ 0,002 | ~US$ 0,04 |
| Secrets Manager (1 secret, ~US$ 0,40/mês + chamadas) | ~US$ 0,001 | ~US$ 0,01 |
| **Total ligado** | **~US$ 0,02** | **~US$ 0,46** |

O banco é a parte mais barata da solução (o cluster do repo #2 custa
~US$ 4,70/dia). Ainda assim, com US$ 50 de crédito compartilhados entre EKS e
RDS, o RDS deve ser destruído junto com o cluster ao fim de cada sessão de
trabalho. Contas elegíveis ao Free Tier do RDS (750 h/mês de `t3.micro`) podem
ter custo zero na instância.

## Validação prevista

- **A cada PR:** `terraform fmt -check`, `validate` e `plan` executados pelo
  `pr.yml` contra o state real da conta configurada nas *Variables*.
- **Após o `apply`:** conferir no console (ou via CLI) que:
  - a instância `mecanica-db-prod` está `available` e `Publicly accessible = No`;
  - o Security Group `mecanica-db-sg` tem uma única regra de entrada, `5432/tcp`
    com origem no SG do cluster;
  - `aws secretsmanager get-secret-value --secret-id mecanica-db-credentials`
    retorna o JSON com `host` igual ao output `db_endpoint` (sem a porta).
- **Integração:** um pod no cluster (repo #4) conecta usando apenas o secret;
  a Lambda (repo #1) autentica um cliente `ATIVO` consultando a tabela
  `clientes` criada pelas migrations da aplicação.

## Riscos e mitigações

| Risco | Mitigação |
| --- | --- |
| Credenciais do Learner Lab expiram antes do `apply` terminar (~5–10 min para criar o RDS) | Renovar os três Secrets imediatamente antes de disparar; `apply` é idempotente, basta reexecutar pelo `workflow_dispatch` |
| `skip_final_snapshot = true` + `recovery_window_in_days = 0`: um `destroy` apaga banco e secret sem volta | Aceito para o escopo acadêmico; os dados são recriados pelas migrations e fixtures da aplicação |
| Ordem de aplicação entre repositórios: o repo #2 precisa existir antes deste, e este antes dos repos #1 e #4 | Documentado no README de cada repositório; os IDs entram por *Variables*, então uma recriação do cluster exige atualizar `VPC_ID`, `SUBNET_IDS` e `ALLOWED_SG_ID` aqui |
| Subnets públicas (herdadas da VPC default do repo #2) | `publicly_accessible = false`: o RDS não recebe IP público, e o SG só aceita o cluster |
| Não há workflow de `destroy` | Executar `terraform destroy` localmente com o `backend.hcl` da conta; avaliar adicionar o workflow como no repo #2 |

## Questões em aberto

- Adicionar um workflow `destroy` manual, alinhado ao repo #2, para reduzir o
  risco de recurso esquecido.
- Alinhar a tabela de variáveis do README principal com o código
  (`db_engine_version` hoje é `17`, não `16.1`).
- O secret é compartilhado por dois consumidores (API e Lambda) com a
  credencial master. Se o grupo quiser separar usuários por serviço, será um
  novo ADR e um passo de bootstrap de roles no PostgreSQL.
