# ADR-002: Credenciais geradas pelo Terraform e entregues apenas pelo AWS Secrets Manager

- **Status:** Aceito
- **Data:** 2026-09-15
- **Repositório:** fiap-soat-mecanica-api-db (banco de dados gerenciado)
- **Decisores:** grupo do Tech Challenge — Fase 3

## Contexto

O Tech Challenge proíbe credenciais em código e pede que segredos fiquem em
um gerenciador apropriado. Dois componentes precisam se conectar ao banco: a
API no Kubernetes (#4) e a Lambda de autenticação (#1). Cada um roda em outro
repositório, com pipeline própria, e nenhum deles deve depender do state do
Terraform deste repositório.

No Learner Lab não é possível criar IAM Roles, então não há como restringir a
leitura do secret a uma identidade específica: tudo roda com `LabRole`. Ainda
assim, a senha não deve passar por pessoas, por GitHub Secrets nem por outputs.

## Decisão

1. A senha master é gerada por `random_password` (16 caracteres, sem
   especiais) **no momento do `apply`**. Ninguém a define nem a conhece.
2. O Terraform grava em um secret do **AWS Secrets Manager** chamado
   `mecanica-db-credentials` um JSON com tudo que um cliente precisa:

   ```json
   { "username": "...", "password": "...", "dbname": "...", "port": 5432, "host": "..." }
   ```

3. Os únicos outputs deste repositório são `db_endpoint` (host:porta) e
   `db_secret_arn`. **A senha não é output**, nem mesmo `sensitive`.
4. Os consumidores (#1 e #4) recebem apenas o ARN (ou o nome) do secret e leem
   as credenciais em tempo de execução pela API do Secrets Manager.
5. `recovery_window_in_days = 0`: um `destroy` apaga o secret imediatamente,
   permitindo recriá-lo com o mesmo nome no mesmo dia — necessário para o
   ciclo destroy/apply diário do Learner Lab.
6. Sem caracteres especiais na senha para evitar problemas de escape em URLs
   de conexão JDBC e em variáveis de ambiente.

## Consequências

**Positivas**
- Nenhuma credencial em código, em GitHub Secrets ou em output. A senha existe
  apenas no state (cifrado no S3) e no Secrets Manager.
- Um único ponto de verdade para host, porta, banco, usuário e senha: se o RDS
  for recriado, o secret é atualizado no mesmo `apply` e os consumidores não
  precisam de nova configuração.
- Consumidores desacoplados do state deste repositório: só precisam do ARN,
  que é estável enquanto o secret existir.

**Negativas / riscos**
- O secret carrega a credencial **master** e é compartilhado por dois
  serviços. Separar usuários por serviço (menor privilégio) exigiria um passo
  de bootstrap no PostgreSQL — fora do escopo atual.
- Sem IAM Roles no Learner Lab, qualquer workload com `LabRole` consegue ler
  o secret. A restrição de rede (ADR-003) é a barreira efetiva.
- Senha de 16 caracteres alfanuméricos: adequada para o escopo; em produção
  real, aumentar o tamanho e habilitar rotação automática do Secrets Manager.
- A senha fica em texto claro no state. O bucket S3 precisa permanecer privado
  e o state nunca deve ser publicado como artefato de pipeline.

## Alternativas consideradas

| Alternativa | Motivo da rejeição |
| --- | --- |
| Senha definida manualmente em GitHub Secrets e passada por `TF_VAR` | Conhecida por quem cadastrou; cópia em cada repositório consumidor; rotação manual em vários lugares |
| Output `sensitive = true` com a senha | Ainda legível em `terraform output -raw` e no state; acopla consumidores ao state deste repo |
| SSM Parameter Store (SecureString) | Funciona, mas sem rotação nativa; os repos #1 e #4 já esperavam Secrets Manager |
| `manage_master_user_password` do RDS (secret gerenciado pela AWS) | O secret gerado pela AWS não inclui `host`, `dbname` e `port` no formato esperado pelos consumidores, e o nome não é controlado |
