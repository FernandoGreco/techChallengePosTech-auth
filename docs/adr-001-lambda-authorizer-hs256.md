# ADR-001: Lambda Authorizer com JWT HS256 no API Gateway HTTP API

- **Status:** Aceito
- **Data:** 2026-10-27
- **Relacionado:** [RFC-001](rfc-001-estrategia-autenticacao.md)

## Contexto

As rotas da aplicação precisam ser protegidas por um token emitido na autenticação via CPF. A aplicação já valida JWT HS256 com segredo compartilhado.

O API Gateway HTTP API oferece dois tipos de authorizer:
- **JWT nativo:** exige um emissor OIDC com JWKS, ou seja, chaves assimétricas.
- **Lambda (REQUEST).**

## Decisão

- Usar **API Gateway HTTP API** com um **Lambda Authorizer** que valida JWT **HS256**:
  - aceita somente esse algoritmo;
  - exige `sub`;
  - usa resposta simples (`isAuthorized`);
  - guarda o resultado em cache por 5 minutos, com o header `Authorization` como chave.
- O contexto do authorizer (`sub`, `papel`) é injetado na aplicação como `x-cliente-id` e `x-usuario-papel`, em modo `overwrite`.

## Consequências

**Positivas**
- Um só formato de token para clientes (CPF) e funcionários (e-mail e senha).
- Token inválido é barrado no gateway, sem consumir recursos do cluster.
- O cache reduz as invocações do authorizer e a latência.

**Negativas**
- É uma Lambda a mais para manter e monitorar. Ela tem alarme próprio no CloudWatch.
- O segredo é compartilhado entre a Lambda, o authorizer e a aplicação. A troca precisa ser coordenada entre os repositórios.
- Por causa do cache, um token revogado continua aceito por até 5 minutos. Isso é aceitável, porque ainda não existe revogação.
