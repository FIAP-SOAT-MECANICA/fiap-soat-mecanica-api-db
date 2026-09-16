# ADR-003: Rede recebida do repositório Kubernetes e acesso restrito ao Security Group do cluster

- **Status:** Aceito
- **Data:** 2026-09-15
- **Repositório:** fiap-soat-mecanica-api-db (banco de dados gerenciado)
- **Decisores:** grupo do Tech Challenge — Fase 3

## Contexto

O cluster EKS (repo #2) roda na **VPC default** da conta, em subnets públicas,
e expõe como outputs `vpc_id`, `subnet_ids` e `cluster_security_group_id`
(com a descrição explícita "o RDS deve liberar 5432 para este SG"). A API (#4)
roda nesses nodes e a Lambda de autenticação (#1) usa as mesmas subnets e o
mesmo Security Group que o banco autoriza.

O banco precisa ser alcançável por esses dois consumidores e por mais ninguém.
No Learner Lab, cada integrante tem uma conta, então IDs de VPC, subnets e SG
mudam de conta para conta e mudam de novo quando o cluster é destruído e
recriado.

## Decisão

1. **Este repositório não cria rede.** `vpc_id`, `subnet_ids` e
   `allowed_security_group_id` são variáveis obrigatórias, preenchidas com os
   outputs do repo #2 (na pipeline, pelas *Variables* `VPC_ID`, `SUBNET_IDS` e
   `ALLOWED_SG_ID`).
2. Cria-se um `aws_db_subnet_group` (`mecanica-db-subnet-group`) com as
   subnets recebidas. O RDS exige subnets em pelo menos duas AZs; o repo #2 já
   filtra `us-east-1e`, que o EKS não aceita.
3. Cria-se um `aws_security_group` (`mecanica-db-sg`) na VPC recebida, com:
   - **ingress** apenas na porta `db_port` (`5432`), protocolo TCP, com origem
     **exclusivamente** o Security Group `allowed_security_group_id`
     (referência por SG, não por CIDR);
   - **egress** liberado (padrão para o RDS enviar respostas e alcançar
     endpoints da AWS).
4. `publicly_accessible = false`: o RDS não recebe IP público, mesmo estando
   em subnets públicas.
5. `SUBNET_IDS` é passada como lista JSON (`["subnet-a","subnet-b"]`) porque a
   variável é `list(string)`; uma string separada por vírgula falha no `plan`.

## Consequências

**Positivas**
- Sem VPC peering, NAT ou VPC endpoints: RDS e consumidores estão na mesma
  VPC e se resolvem por DNS interno.
- Regra de acesso por **referência de SG**: quando o node group escala ou é
  substituído, os novos nodes continuam autorizados sem tocar neste
  repositório. Não há `0.0.0.0/0` em nenhuma regra de entrada.
- Contrato explícito entre repositórios: o que este precisa está declarado
  em `variables.tf`, e o que o repo #2 oferece está em `outputs.tf` dele.
- Trocar o provedor de rede (VPC dedicada, outra conta) não altera este
  código — só os valores das variáveis.

**Negativas / riscos**
- Ordem de aplicação obrigatória: o repo #2 antes deste. Se o cluster for
  recriado com outro SG, as *Variables* deste repositório precisam ser
  atualizadas e o `deploy.yml` reexecutado.
- Subnets públicas herdadas da VPC default: mitigado por
  `publicly_accessible = false` e pela regra de ingress restrita.
- Acesso local ao banco para depuração (por exemplo, `psql` da máquina do
  desenvolvedor) não é possível sem um bastion ou port-forward por um pod do
  cluster. Aceito: reforça que o único caminho é pelos consumidores.
- Sem TLS obrigatório na conexão (`rds.force_ssl` não é configurado): a
  Lambda já exige TLS por conta própria; a API deve fazer o mesmo.

## Alternativas consideradas

| Alternativa | Motivo da rejeição |
| --- | --- |
| Criar VPC e subnets privadas neste repositório | Mais recursos e custo (NAT); exigiria peering com a VPC do cluster, coordenado entre dois repositórios |
| Ler a VPC default por `data source` aqui, sem variáveis | Funciona hoje, mas amarra este repositório à escolha de rede do repo #2; a variável mantém o contrato explícito e permite outra VPC sem mudar código |
| Ingress por CIDR da VPC (`172.31.0.0/16`) | Libera qualquer recurso da VPC, não só o cluster; a referência por SG é mais restrita |
| `publicly_accessible = true` com SG restrito | Expõe um IP público sem necessidade; contraria o requisito de segurança do desafio |
