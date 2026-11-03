# Normalização e cardinalidades — análise final, 02/11/2026

Fontes: DDL real de `postgres`, DAU/catálogo e comparação com Flyway V1–V4/entidades do Spring. Não foi encontrado DER oficial versionado nos artefatos inspecionados; a representação textual abaixo deriva do schema e não substitui um DER oficial.

**Conclusão:** não certificar todo o conjunto como 3FN estrita. O núcleo comercial tem atributos escalares e associações separadas, mas `Inventories`/`Products` conservam redundância condicional de empresa e `Data_Catalog` repete metadados de tabela por coluna. As pendências estão identificadas, não escondidas por PKs artificiais.

## Chaves, dependências e formas normais

Todas as relações possuem `id → demais atributos` pela PK. A tabela também considera as chaves naturais: PK simples não basta para provar 2FN quando existem outras candidatas compostas.

| Relação | Chaves candidatas e dependências relevantes | Avaliação fundamentada |
|---|---|---|
| Companies | id; cnpj; email, não nulos/únicos. Cada um determina nome/plano. | 1FN/2FN/3FN no domínio conhecido; nome/plano não são chaves. |
| Users | id; cpf; email, não nulos/únicos. Determinam nome, sobrenome, nascimento e credencial. | 1FN/2FN/3FN conhecida; idade não é armazenada como redundância. |
| Sectors | id; (company_id,name). Tipo depende do setor completo, não apenas da empresa/nome. | 1FN/2FN/3FN sob essa regra. |
| Aisles | id; (sector_id,position). | 1FN/2FN/3FN; posição é relativa ao setor, CHECK > 0. |
| Shelves | id; corredor e capacidade pertencem à prateleira. | 1FN/2FN/3FN; empresa não é duplicada. |
| Employees | id; users_id UNIQUE NOT NULL. Ambos determinam empresa/posição. | 1FN/2FN/3FN: users_id é superchave, não uma dependência transitiva não-chave. |
| Customers | id; users_id UNIQUE NOT NULL. | Mesma conclusão. Usuário pode ser cliente e funcionário simultaneamente. |
| Inventories | id; sector_id opcional e não único. Setor atribuído determina a empresa do setor. | 1FN/2FN; redundância condicional de company_id impede afirmar 3FN estrita. |
| Categories | id; (company_id,category). | 1FN/2FN/3FN no domínio de categoria por empresa. |
| Products | id; nome não é UNIQUE no DDL. Categoria opcional determina sua empresa e deve concordar com company_id. | 1FN/2FN; problema condicional semelhante a Inventories. Não assumir nome → marca/preço. |
| Inventory_Employees | id; (inventory_id,employee_id), par obrigatório. | Sem atributo parcialmente dependente: 1FN/2FN/3FN. Empresa consistente é outra restrição. |
| Employee_Aisles | id; (employee_id,aisle_id), par obrigatório. | 1FN/2FN/3FN sob semântica de atribuição. |
| Shelf_Employees | id; UNIQUE(shelf_id,employee_id), ambos aceitam NULL. | UNIQUE com NULL não é chave candidata clássica. Associação incompleta é permitida fisicamente; não inventar NOT NULL inexistente. |
| Product_Shelves | id; (product_id,shelf_id). Quantidade depende do par completo. | 1FN/2FN/3FN; quantidade não depende somente de um dos lados. CHECK > 0. |
| Product_Inventories | id; (inventory_id,product_id). Quantidade depende do par completo. | 1FN/2FN/3FN; CHECK permite zero. |
| Restockings | id; quatro FKs representam papéis do evento; nenhuma é chave isolada. | 1FN/2FN/3FN conhecida; bruto e avarias são fatos diferentes, líquido é derivável. DDL não exige avarias <= bruto ou cargo STOCKER. |
| Alerts | id; estado, abertura, resolução e descrição pertencem ao evento. | 1FN/2FN/3FN conhecida; cronologia e obrigatoriedade de resolução são integridade, não normalização. Não são plenamente impostas no DDL. |
| Purchases | id; cliente obrigatório, data opcional, status restrito. | 1FN/2FN/3FN; total não é duplicado e empresa vem do cliente. |
| Purchase_Products | id; (purchase_id,product_id). Quantidade e preço unitário dependem da linha completa. | 1FN/2FN/3FN; preço histórico da linha não é determinado pelo preço atual mutável de Products. Não remover amount alegando redundância. |
| Audits | id; operação/tabela/registro/autor/horário e snapshots JSONB. | Registro documental histórico. JSONB é domínio opaco; não certificar seus subcampos como relações em 3FN. `users` é CURRENT_USER SQL, não FK de pessoa. |
| User_Accesses | id; (user_id,company_id,access_date). first/last dependem do triplo. | 1FN/2FN/3FN sob política DAU. user_id não determina empresa globalmente: subtipos podem autorizar duas empresas diferentes. |
| Data_Catalog | id; (schema_name,table_name,column_name). (schema_name,table_name) → table_description. | Cache documental regenerável, não 2FN/3FN estrita pela chave natural; descrição depende de parte da chave. |

O Spring também possui outbox `restocking_history_delivery` e `restocking_history_bypass`. Payload, empresa e semana são snapshots de entrega; não substituir por JOINs a entidades atuais sem preservar a semântica temporal. Esta análise não certifica esses documentos históricos como relações comerciais normalizadas.

## Setor opcional e empresa: dependência e anomalia

Pela regra de negócio "setor e inventário da mesma empresa", nas linhas com setor existe `id → sector_id → company_id`. Vários inventários podem compartilhar setor; sector_id não é superchave. Permitir NULL mantém inventários sem localização, mas não elimina a redundância nas linhas localizadas. Isso é uma dependência condicional, considerando que o SQL com NULL não corresponde integralmente ao modelo relacional clássico.

Foi demonstrado em transação revertida que inventário de empresa 1 com setor 11 da empresa 2 é aceito: ambas as FKs são válidas individualmente. Alterar a empresa do setor também pode gerar anomalia sem violar essas FKs. O mesmo vale para Products.company_id e categoria atribuída de outra empresa.

Não remover company_id simplesmente: sem setor/categoria ele ainda identifica o proprietário empresarial. Proposta segura, **não aplicada como migração destrutiva nesta entrega**:

1. Formalizar propriedade empresarial separada de localização/classificação opcional.
2. Avaliar `Inventory_Sectors(inventory_id,sector_id)` e `Product_Categories(product_id,category_id)`, com no máximo uma associação por entidade, como decomposição do modelo.
3. Usar expand/contract: criar associações, auditar/backfill somente dados coerentes, adaptar Services/mappers/dataload e manter leitura compatível até a transição.
4. Impor coerência empresarial também em UPDATE dos pais e filhos; trigger somente de INSERT no filho não resolve mudanças de setor/empresa/categoria ou concorrência.
5. Separar metadados de tabela/coluna do catálogo, ou assumir explicitamente sua materialização documental regenerável.

Essa mudança afeta FKs, ORM e colunas consumidas por consultas/views, inclusive dependências do Daniel. Não foi executada sob prazo curto sem coordenar essas interfaces. CHECKs de coerência melhoram integridade, mas não removem redundância nem comprovam 3FN.

## Cardinalidades — representação textual do DDL

Pais podem ter zero filhos; FK não exige população mínima do lado pai.

- Companies 1 → 0..N Sectors, Employees, Inventories, Categories, Products e Customers; cada filho tem uma empresa obrigatória.
- Users 1 → 0..1 Employees e 1 → 0..1 Customers; subtipos não são mutuamente exclusivos.
- Sectors 1 → 0..N Aisles; Aisles 1 → 0..N Shelves; cada filho tem um pai obrigatório.
- Sectors 1 → 0..N Inventories; inventário tem 0..1 setor.
- Categories 1 → 0..N Products; produto tem 0..1 categoria no DDL.
- Inventories ↔ Employees e Employees ↔ Aisles: N:N com par obrigatório/único nas associativas.
- Employees ↔ Shelves: N:N, mas ambas as FKs são opcionais na tabela física.
- Products ↔ Inventories e Products ↔ Shelves: N:N com quantidade por par único.
- Customers 1 → 0..N Purchases; Purchases 1 → 0..N Purchase_Products. Cada item possui um produto e uma compra. "Concluída exige itens" não é garantido somente por essas FKs.
- Cada Restocking tem um Inventory, Employee, Shelf e Product; cada pai pode ter 0..N eventos.
- Cada Alert tem uma Shelf e 0..1 Employee/Product; vínculo empresarial não é imposto por essas FKs.
- User_Accesses associa usuário/empresa/dia, com UNIQUE do triplo.
- Referências por texto/JSON de Audits e Data_Catalog não são FKs comerciais.

## Banco, backend e lacunas verificadas

| Regra | Banco | Backend / conclusão |
|---|---|---|
| Produto/categoria da mesma empresa | INSERT incoerente aceito. | Category não mapeia company_id; correção coordenada do módulo, inclusive cache/escopo, permanece necessária. |
| Estoque/setor da mesma empresa | INSERT incoerente aceito. | Mapper agora deriva empresa do setor; update para setor de outra empresa é recusado com 403. Teste em PostgreSQL real. |
| Produto/estoque, produto/prateleira, funcionário/corredor | FKs individuais não comparam empresas; casos aceitos. | Cobertura depende do endpoint; não certificada universalmente. |
| Reposição | INSERT direto incoerente aceito. | Procedure compara empresas; RestockingAccess/Service autorizam ator e vínculos. Não protege SQL direto. |
| Compra/produto do cliente | INSERT direto incoerente aceito. | ETL/RPA anteriormente validado compara mapa/cliente/empresa, não substitui constraint geral. Não foi refeito. |

Divergências ORM/DDL adicionais: Sectors.name é UNIQUE por empresa no DDL, global no JPA; Product.name não é UNIQUE no DDL, mas é no JPA; Product.category é opcional no DDL e obrigatória no JPA. Categories.company_id é NOT NULL no banco e não mapeado na entidade. `ddl-auto=create-drop` pode ocultar essas diferenças; DAU foi testado com Flyway e `ddl-auto=validate`, sem usar isso como certificação de todos os CRUDs.

## Evidências

`ScriptSQL_Kairos_model_validation.sql` é somente leitura: 13 checks na carga corrigida retornaram zero. `test_company_constraints_local.sql`, guardado para banco local, aceitou sete INSERTs adversariais e fez ROLLBACK: comprova lacunas de enforcement, não uma proteção nova.

A carga observada tem **1.050.000 registros comerciais**. A fórmula antiga gerava 5.344 alertas resolvidos antes da abertura; a nova fórmula zerou esse check em outro banco novo. Não foram corrigidas linhas existentes ou removidas colunas. Não foram alteradas views dimensionais/fatos/indicadores do Daniel.
