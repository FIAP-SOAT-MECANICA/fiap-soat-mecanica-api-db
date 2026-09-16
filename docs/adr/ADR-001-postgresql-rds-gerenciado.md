# ADR-001: PostgreSQL gerenciado no Amazon RDS, fora do cluster Kubernetes

- **Status:** Aceito
- **Data:** 2026-09-15
- **Repositório:** fiap-soat-mecanica-api-db (banco de dados gerenciado)
- **Decisores:** grupo do Tech Challenge — Fase 3

## Contexto

O Tech Challenge exige um "banco de dados gerenciado" e pede que o grupo
justifique a escolha entre SQL e NoSQL. A aplicação da Mecânica do Braia usa
PostgreSQL desde a Fase 1: o domínio é relacional (clientes, veículos, ordens
de serviço, serviços, peças e orçamentos com integridade referencial), as
consultas dependem de junções e o schema é versionado por migrations no
repositório da aplicação (#4). A Function de autenticação (#1) também lê a
tabela `clientes` por SQL.

O ambiente é o AWS Academy Learner Lab: crédito de ~US$ 50 por conta, sem
criação de IAM Roles, sessões de 4 horas e recursos que persistem após a
sessão. O cluster Kubernetes (#2) roda dois nodes `t3.medium`, que já hospedam
a API, o gateway e o operador de observabilidade.

## Decisão

Provisionar **uma instância Amazon RDS PostgreSQL**, gerenciada pela AWS,
**fora do cluster**, com a menor configuração que atende a demonstração:

| Parâmetro | Valor | Motivo |
| --- | --- | --- |
| Identificador | `mecanica-db-prod` | Ambiente único (ver ADR-004) |
| Engine / versão | `postgres` `17` (major) | Mesmo engine das fases anteriores; só a major deixa o RDS escolher a minor disponível |
| Classe | `db.t3.micro` | Menor instância; ~US$ 0,017/h; elegível ao Free Tier |
| Armazenamento | 10 GB | Suficiente para dados de demonstração |
| Multi-AZ | `false` | Dobraria o custo sem valor para a avaliação |
| `publicly_accessible` | `false` | Ver ADR-003 |
| `skip_final_snapshot` | `true` | `destroy` sem etapa manual; dados são recriados por migrations |
| `apply_immediately` | `true` | Mudanças não esperam janela de manutenção; sessões curtas |

Todos os parâmetros são variáveis com default; nenhum precisa ser informado
para o caso padrão além de `db_name` e dos três IDs de rede.

O repositório entrega um banco **vazio**. Schema, índices e dados iniciais são
responsabilidade das migrations da aplicação (#4), que já existiam antes deste
repositório e continuam sendo a única fonte de verdade da estrutura.

## Consequências

**Positivas**
- Atende literalmente o requisito de banco gerenciado: backup automático,
  patches, monitoramento e failover (se habilitado) ficam com a AWS.
- Nenhuma mudança na aplicação: mesmo engine, mesmo driver, mesmas migrations.
- O banco não concorre com a API por CPU e memória dos nodes do cluster.
- Custo previsível e baixo (~US$ 0,46/dia com armazenamento e secret).

**Negativas / riscos**
- Single-AZ e sem snapshot final: uma falha de AZ ou um `destroy` acidental
  perde os dados. Aceito porque tudo é recriável por migrations e fixtures.
- `db.t3.micro` tem CPU em créditos (burstable); um teste de carga longo pode
  degradar. Para a demonstração do HPA, a carga esperada é curta.
- Versão informada só pela major: um `apply` futuro pode adotar uma minor mais
  nova. É o comportamento desejado no Learner Lab; em produção real, fixar a
  minor.

## Alternativas consideradas

| Alternativa | Motivo da rejeição |
| --- | --- |
| DynamoDB (NoSQL) | Domínio relacional com junções e integridade referencial; exigiria reescrever persistência, migrations e a consulta da Lambda |
| Aurora PostgreSQL | Instância mínima muito mais cara; Serverless v2 tem custo mínimo por ACU; sem ganho para carga de demonstração |
| PostgreSQL em StatefulSet no EKS | Não é gerenciado; backup e patch manuais; disputa recursos com a API; volume EBS precisaria de CSI driver (IAM) |
| RDS Multi-AZ | Custo dobrado sem valor para a avaliação; a variável `multi_az` já permite ligar depois |
