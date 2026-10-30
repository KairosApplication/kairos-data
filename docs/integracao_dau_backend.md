# Kairos | Contrato de integração DAU com backend

Responsável: backend principal (alinhamento com Dias).

A função PostgreSQL `register_user_access(p_user_id INT, p_company_id INT)` registra uma vez por dia o acesso de um usuário **autenticado** a uma empresa. A mesma pessoa pode acessar várias vezes no dia sem aumentar DAU; a função atualiza `last_seen_at`.

## Fluxo esperado

1. Backend valida login/token e resolve o ID real do usuário (`Users.id`).
2. Backend determina a empresa autorizada com base no vínculo `Employees` ou `Customers` (não aceitar `company_id` arbitrário do cliente).
3. Após autenticação válida ou atividade que represente uso efetivo, backend executa:

```sql
SELECT register_user_access($1, $2);
```

4. BI consulta o resultado com filtro da empresa autorizada:

```sql
SELECT access_date, daily_active_users
FROM vw_dau_daily
WHERE company_id = $1
ORDER BY access_date DESC
LIMIT 30;
```

## Critérios de teste

- Dois acessos do mesmo usuário na mesma empresa no mesmo dia => DAU conta **1**.
- Dois usuários distintos na mesma empresa => DAU conta **2**.
- Vínculo usuário/empresa inexistente => a função levanta exceção.
- Um usuário legítimo em empresas distintas pode ter registro diário separado para cada empresa.
- A chamada não deve registrar probes, health checks ou tentativas de login inválidas.
- `first_seen_at` é mantido e `last_seen_at` deve se atualizar.

## Importante

- Sem evento vindo do backend, `User_Accesses` fica vazia, porque o PostgreSQL não enxerga acessos HTTP por conta própria.
- O backend deve decidir se falha no registro do DAU pode ou não afetar a experiência do login. Em geral, é preferível registrar erros/retentar sem impedir uso legítimo da aplicação, conforme arquitetura do time.
- Segurança da função envolve permissões de usuário/role no PostgreSQL além da checagem lógica do vínculo.
