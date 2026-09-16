# ADR-004: State remoto em S3 com lock nativo, backend parametrizado e ambiente único de produção

- **Status:** Aceito
- **Data:** 2026-09-15
- **Repositório:** fiap-soat-mecanica-api-db (banco de dados gerenciado)
- **Decisores:** grupo do Tech Challenge — Fase 3

## Contexto

O enunciado pede deploy automatizado para homologação e produção. O grupo já
decidiu, no repo #2 (ADR-002 de lá), manter um único cluster de produção por
causa do crédito do Learner Lab. O banco segue a mesma lógica: um segundo RDS
custaria pouco (~US$ 0,46/dia), mas só faria sentido junto de um segundo
cluster, que é o que não cabe no orçamento.

O state do Terraform precisa ser compartilhado entre a pipeline e os
desenvolvedores, com lock para evitar `apply` concorrente. O bloco `backend`
do Terraform não aceita variáveis, e os nomes de bucket mudam de conta para
conta (quatro contas durante o desenvolvimento, uma na entrega).

## Decisão

### Backend S3 com lock nativo

- `backend "s3" { use_lockfile = true }`: o lock é um objeto `.tflock` no
  próprio bucket (Terraform ≥ 1.10). Nenhuma tabela DynamoDB.
- `bucket`, `key` e `region` **não ficam no código**. Entram por
  `-backend-config`:
  - localmente, via `backend.hcl` (ignorado pelo Git; `backend.hcl.example`
    é o template versionado);
  - na pipeline, via *Variables* `TF_STATE_BUCKET`, `TF_STATE_KEY` e
    `TF_STATE_REGION`.
- Chave do state: `db/prod/terraform.tfstate`. O prefixo `db/` separa este
  repositório dos demais no mesmo bucket; `prod/` reserva espaço para outros
  ambientes sem refatorar.
- Terraform fixado em `>= 1.14.5, < 1.16.0` (a pipeline usa `1.14.5`);
  providers `aws ~> 5.0` e `random ~> 3.6`; `.terraform.lock.hcl` versionado
  para reprodutibilidade entre contas.

### Ambiente único de produção

- Uma instância, `mecanica-db-prod`, sem homologação.
- A validação antes de afetar produção é feita pelo **PR**: `fmt -check`,
  `validate` e `plan` no `pr.yml`, com branch protection exigindo o check
  verde e revisão antes do merge.
- O `apply` roda no merge em `main` (`deploy.yml`) ou manualmente por
  `workflow_dispatch`, para reaplicar após renovar as credenciais do Learner
  Lab sem commit novo.

## Consequências

**Positivas**
- Um único recurso de backend (o bucket), criado uma vez por conta; migrar
  para a conta final é apontar `backend.hcl`/*Variables* para o bucket dela e
  rodar `apply`.
- Nenhum account ID, ARN ou bucket no código versionado.
- Pipeline simples de explicar e de demonstrar; mesmo padrão do repo #2.

**Negativas / riscos**
- Desvio explícito do enunciado (sem homologação). Este ADR e o ADR-002 do
  repo #2 registram a justificativa e devem ser citados na entrega.
- Um `plan` aprovado por engano vai direto para produção. Mitigação: revisão
  obrigatória, e o banco é recriável por migrations.
- O bucket precisa existir antes do primeiro `init`; este repositório não o
  cria (o repo #2 tem um script de bootstrap para isso).
- Sem workflow de `destroy`: o ciclo diário do Learner Lab depende de
  `terraform destroy` local. Candidato a melhoria, alinhado ao repo #2.
- Se um dia houver homologação: um segundo `backend.hcl` com
  `key = "db/homolog/terraform.tfstate"`, um `terraform.tfvars` próprio e um
  identificador parametrizado para a instância. A estrutura atual não exige
  reestruturação.

## Alternativas consideradas

| Alternativa | Motivo da rejeição |
| --- | --- |
| S3 + DynamoDB para lock | Recurso extra por conta sem ganho; o lockfile nativo resolve |
| Valores de backend fixos no `backend.tf` | Quebraria em cada conta diferente; exigiria commit para trocar de conta |
| Terraform Cloud | Dependência externa; credenciais rotativas do Learner Lab complicam a integração |
| Duas instâncias (homolog + prod) | Só faria sentido com dois clusters, o que o crédito não comporta |
| Homologação efêmera por PR | Criar e destruir um RDS leva ~10–15 min por ciclo; sessões de 4h e credenciais rotativas tornam o fluxo frágil |
