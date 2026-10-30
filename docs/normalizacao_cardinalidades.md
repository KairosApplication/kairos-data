# Kairos | Revisão de modelagem, cardinalidades e 3FN

Este documento é um **rascunho para validação** com base na estrutura conhecida do Kairos. Deve ser confrontado com o `CREATE TABLE` atual e com o diagrama ER antes de ser apresentado como comprovação definitiva da 3ª Forma Normal.

## Cardinalidades principais

| Relação | Cardinalidade | Como é representada |
|---|---|---|
| `Companies` -> `Employees` | 1:N | `Employees.company_id` |
| `Users` -> `Employees` | 1:0..1 | `Employees.users_id UNIQUE` |
| `Companies` -> `Customers` | 1:N | `Customers.company_id` |
| `Users` -> `Customers` | 1:0..1 | `Customers.users_id UNIQUE` |
| `Companies` -> `Sectors` | 1:N | `Sectors.company_id` |
| `Sectors` -> `Aisles` | 1:N | `Aisles.sector_id` |
| `Aisles` -> `Shelves` | 1:N | `Shelves.aisle_id` |
| `Companies` -> `Products` | 1:N | `Products.company_id` |
| `Companies` -> `Categories` | 1:N | `Categories.company_id` |
| `Categories` -> `Products` | 1:N | `Products.category_id` (pode ser NULL) |
| `Companies` -> `Inventories` | 1:N | `Inventories.company_id` |
| `Sectors` -> `Inventories` | 1:N | `Inventories.sector_id` (pode ser NULL) |
| `Employees` <-> `Inventories` | N:N | `Inventory_Employees` |
| `Employees` <-> `Shelves` | N:N | `Shelf_Employees` |
| `Employees` <-> `Aisles` | N:N | `Employee_Aisles` |
| `Products` <-> `Shelves` | N:N | `Product_Shelves` (inclui quantidade) |
| `Products` <-> `Inventories` | N:N | `Product_Inventories` (inclui quantidade) |
| `Customers` -> `Purchases` | 1:N | `Purchases.customer_id` |
| `Purchases` -> `Purchase_Products` | 1:N | `Purchase_Products.purchase_id` |
| `Products` -> `Purchase_Products` | 1:N | `Purchase_Products.product_id` |
| `Employees` -> `Restockings` | 1:N | `Restockings.employee_id` |
| `Products` -> `Restockings` | 1:N | `Restockings.product_id` |
| `Shelves` -> `Restockings` | 1:N | `Restockings.shelf_id` |
| `Inventories` -> `Restockings` | 1:N | `Restockings.inventory_id` |
| `Employees` -> `Alerts` | 1:N (opcional) | `Alerts.employee_id` |
| `Products` -> `Alerts` | 1:N (opcional) | `Alerts.product_id` |
| `Shelves` -> `Alerts` | 1:N | `Alerts.shelf_id` |

**Notação:** `1:0..1` significa que um usuário pode não ter registro no subtipo; cada registro do subtipo corresponde a um único usuário, e a restrição UNIQUE impede duplicações no subtipo. Isso não impede que a mesma pessoa tenha registros simultaneamente em `Employees` e `Customers`.

## Avaliação preliminar da normalização

- **1FN:** as tabelas apresentadas usam colunas atômicas e identificadores de registros. O catálogo e a verificação manual do schema ajudam a comprovar.
- **2FN:** as entidades principais possuem PKs simples, e relações N:N usam tabelas associativas; é necessário conferir as dependências funcionais e a presença de atributos dependentes de combinações UNIQUE.
- **3FN:** exige provar ausência de dependências transitivas não justificadas. **Ponto a revisar:** em `Inventories`, quando `sector_id` não é nulo, o setor identifica sua empresa; manter `company_id` junto pode introduzir redundância e inconsistências. O mesmo cuidado vale para outras relações entre empresas e entidades filhas.
- A existência de `CHECK`, FKs e `UNIQUE` **não comprova sozinha** que o modelo está na 3FN.
- Integridade multiempresa não é garantida apenas por FKs isoladas. Execute `09_model_validation.sql` e discuta com o time restrições compostas, políticas RLS ou validações transacionais onde fizer sentido.

## Evidências que faltam anexar

1. Diagrama ER atualizado com atributos e cardinalidades.
2. Listagem de PK, UNIQUE e FK reais (query em `09_model_validation.sql`).
3. Descrição das dependências funcionais relevantes.
4. Comprovação de ajustes necessários à 3FN ou justificativas para redundâncias deliberadas.
5. Resultado dos testes de inconsistência entre empresas.
