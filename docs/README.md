# Documentação — banco de dados gerenciado

Decisões e justificativas do repositório `fiap-soat-mecanica-api-db`
(repositório #3 do Tech Challenge — Fase 3). A documentação transversal da
solução (diagrama de componentes geral, diagramas de sequência, modelo ER e
RFCs de nuvem/Kubernetes/autenticação) fica no local definido pelo grupo; aqui
estão apenas as decisões que existem por causa deste componente.

## RFCs

| Documento | Assunto |
| --- | --- |
| [RFC-001](rfc/RFC-001-rds-postgresql-learner-lab.md) | Provisionar o banco gerenciado com Amazon RDS PostgreSQL no AWS Academy Learner Lab: restrições, alternativas, custo, validação |

## ADRs

| Documento | Decisão |
| --- | --- |
| [ADR-001](adr/ADR-001-postgresql-rds-gerenciado.md) | PostgreSQL gerenciado no Amazon RDS (SQL, single-AZ, `db.t3.micro`), fora do cluster Kubernetes; schema é responsabilidade da aplicação |
| [ADR-002](adr/ADR-002-credenciais-secrets-manager.md) | Senha gerada por `random_password` e entregue aos consumidores só pelo AWS Secrets Manager; nenhum output expõe a credencial |
| [ADR-003](adr/ADR-003-rede-desacoplada-sg.md) | Rede recebida por variáveis do repositório Kubernetes; ingress `5432` apenas para o Security Group do cluster; RDS sem endereço público |
| [ADR-004](adr/ADR-004-state-s3-ambiente-unico.md) | State remoto em S3 com lock nativo, `backend.hcl` fora do versionamento e um único ambiente de produção |

## Diagrama do componente

O diagrama específico deste repositório está na seção
[Arquitetura](../README.md#arquitetura) do README principal.

## Convenções

- **RFC** registra uma proposta com alternativas comparadas, custo e riscos —
  escrita antes ou durante a decisão.
- **ADR** registra uma decisão já tomada: contexto, decisão, consequências.
  ADRs não são editados depois de aceitos; uma mudança gera um novo ADR que
  substitui o anterior.
- Numeração sequencial por tipo. Próximos: `RFC-002`, `ADR-005`.
