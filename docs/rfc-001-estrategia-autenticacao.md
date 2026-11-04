# RFC-001: Estratégia de autenticação de clientes via CPF

| | |
|---|---|
| **Status** | Aceita |
| **Autor** | Max (repo 01, auth) |
| **Revisores** | Daisy (aplicação), Felipe (k8s), Fernando (banco) |
| **Data** | 2026-10-27 |

## 1. Contexto

A oficina precisa:
- proteger as rotas sensíveis com **autenticação via CPF**;
- usar uma **função serverless** que valide o CPF, consulte a existência e o status do cliente e emita um **JWT**;
- ter um **API Gateway** como ponto único de entrada.

A aplicação NestJS já tinha um login de funcionários, com e-mail e senha, que emite JWT HS256 (`JWT_SECRET`).

**Restrições do ambiente (AWS Academy Learner Lab):**
- não dá para criar roles IAM nem provedores OIDC;
- as credenciais são temporárias;
- o orçamento é de US$50;
- cada integrante usa uma conta própria.

## 2. Proposta

```
Cliente ──POST /auth/cpf──▶ API Gateway ──▶ Lambda auth ──▶ RDS (clientes)
                                │                 └──▶ JWT HS256 (1h)
Cliente ──Bearer JWT──▶ API Gateway ──▶ Lambda Authorizer ──ok──▶ Aplicação (K8s)
```

1. **`POST /auth/cpf`, público.** A Lambda:
   - normaliza e valida os dígitos verificadores;
   - busca `clientes` com `tipoDocumento = 'CPF'`;
   - devolve 401 se não encontrar e 403 se o cliente estiver inativo;
   - no sucesso, emite um JWT com `sub` (id do cliente), `cpf`, `nome`, `papel: CLIENTE`, `iss` e `exp`, válido por 1 hora.
2. **Rotas da aplicação (`ANY /{proxy+}`):** passam por um **Lambda Authorizer**, que valida a assinatura e a expiração. A decisão fica em cache de 5 minutos por token.
3. **Identidade repassada à aplicação:** o gateway injeta `x-cliente-id`, `x-usuario-papel` e `x-correlation-id`. O modo é `overwrite`, então o cliente não consegue forjar esses headers.
4. **Mesmo segredo nos dois logins:** o login de funcionário (`POST /auth/login`) continua na aplicação e usa o mesmo segredo HS256. Os dois tipos de token passam pelo mesmo authorizer.

## 3. Alternativas consideradas

| Alternativa | Por que não |
|---|---|
| **Amazon Cognito** (custom auth com CPF) | Exige triggers e roles próprias. A configuração fica pesada no Learner Lab, e o CPF não é login nativo. A aplicação também teria que trocar a validação de token. |
| **JWT Authorizer nativo do HTTP API** | Só aceita emissores OIDC com JWKS (RS256). Isso exigiria publicar um JWKS e gerenciar chaves assimétricas. |
| **Autenticação dentro da aplicação** (sem Lambda) | Não atende ao requisito de função serverless, e o processo de autenticação ficaria acoplado ao cluster. |
| **REST API (v1) do API Gateway** | Custa mais e tem latência maior. Os recursos extras dela, como planos de uso e validação de schema, não são necessários aqui. |
| **RS256 com par de chaves** | Melhor para muitos consumidores. Com só a aplicação validando, o HS256 é mais simples e já era o padrão dela. Pode virar uma evolução futura (seção 6). |

## 4. Segurança
- **Transporte e assinatura:** o tráfego é só HTTPS, pelo gateway. O token é assinado e expira em 1 hora. O authorizer aceita **apenas HS256**, o que bloqueia o ataque `alg: none`.
- **Dados pessoais:** o CPF aparece **mascarado** nos logs (`*******8909`).
- **Banco:** a conexão exige SSL. A Lambda usa um usuário de banco próprio, com permissão só de leitura em `clientes` (recomendado).
- **Abuso:** há throttling no stage do gateway (homolog 50/100 rps, prod 100/200).
- **Segredos:** `JWT_SECRET` e `DATABASE_URL` ficam como secrets por environment do GitHub e são injetados pelo Terraform. Nunca entram no repositório.

## 5. Impacto nos outros repositórios
- **Aplicação:**
  - usa o mesmo `JWT_SECRET`;
  - pode confiar em `x-cliente-id` (defesa em profundidade: o `JwtStrategy` continua validando);
  - deve propagar o `x-correlation-id` nos logs;
  - migration opcional: `ativo Boolean @default(true)`.
- **Banco:** o RDS precisa ser público com SSL, com a porta 5432 liberada, porque a Lambda roda em outra conta e fora de VPC.
- **K8s:** expor um endpoint estável (Elastic IP ou DNS) para a variável `APP_BASE_URL`.

## 6. Evolução futura
- Migrar para RS256 com JWKS, o que permite usar o authorizer nativo sem Lambda.
- Usar refresh token e revogação, com lista de bloqueio no DynamoDB.
- Levar o segredo para o Secrets Manager, com rotação, quando houver orçamento.
