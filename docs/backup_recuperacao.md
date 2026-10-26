# Kairos — Procedimento e evidência de backup e recuperação

## Objetivo
Demonstrar que uma cópia lógica do PostgreSQL do Kairos pode ser restaurada em ambiente isolado, preservando estrutura, dados e objetos lógicos.

## Ambiente e ferramentas
- Origem: PostgreSQL 18.6 hospedado na Aiven, banco `kairosdb`.
- Ferramentas: Docker Desktop, imagem `postgres:18`, `pg_dump`, `pg_restore` e `psql`.
- Destino do teste: contêiner local `kairos-restore-test`, banco `kairos_restore`, isolado da Aiven.
- Data do teste: 26/10/2026.
- **Segredos e dados:** não versionar arquivos `.backup`, senhas ou URLs contendo credenciais. Os comandos abaixo usam placeholders e entradas protegidas.

## Backup (origem na Aiven)
No PowerShell, na pasta onde o backup deve ser salvo:

```powershell
$senhaSegura = Read-Host "Senha do PostgreSQL da Aiven" -AsSecureString
$env:PGPASSWORD = [System.Net.NetworkCredential]::new('', $senhaSegura).Password
$env:PGSSLMODE = 'require'

docker run --rm -e PGSSLMODE=require -e PGPASSWORD -v "${PWD}:/backup" postgres:18 pg_dump -h "HOST_DA_AIVEN" -p PORTA_DA_AIVEN -U avnadmin -d kairosdb -F c --no-owner --no-acl -f /backup/kairos_backup.backup

Remove-Item Env:PGPASSWORD
Remove-Item Env:PGSSLMODE
Remove-Variable senhaSegura
```

Observação: `pg_dump` é uma operação de leitura no banco de origem. O cliente precisa ser compatível com o servidor; neste teste foram usados PostgreSQL 18.6 em ambos os lados.

## Inspeção do arquivo

```powershell
Get-Item .\kairos_backup.backup
docker run --rm -v "${PWD}:/backup" postgres:18 pg_restore -l /backup/kairos_backup.backup
```

**Resultado observado:** arquivo de **10.212.444 bytes** (~10,2 MB), formato `CUSTOM` com **251 entradas** no catálogo e banco de origem `kairosdb`. Foram identificados dados de tabelas, sequências, views, índices, triggers, funções e procedures. A listagem do catálogo não substitui o teste de restauração.

## Restauração isolada (Docker)
O comando seguinte cria somente um banco local de teste; nunca use `dropdb` contra a Aiven.

```powershell
docker run -d --name kairos-restore-test -e POSTGRES_PASSWORD=senha_teste_local -e POSTGRES_DB=kairos_restore -v kairos_restore_data:/var/lib/postgresql postgres:18
docker exec kairos-restore-test pg_isready -U postgres

# Se o banco local já tiver sido restaurado parcialmente, recrie APENAS ele:
docker exec kairos-restore-test dropdb -U postgres --if-exists --force kairos_restore
docker exec kairos-restore-test createdb -U postgres kairos_restore

docker run --rm --network container:kairos-restore-test -e PGPASSWORD=senha_teste_local -v "${PWD}:/backup" postgres:18 pg_restore -h localhost -U postgres -d kairos_restore --no-owner --no-acl --exit-on-error --verbose /backup/kairos_backup.backup
$LASTEXITCODE
```

**Resultado observado:** comando concluído com **código de saída `0`**; criação de tabelas, carregamento de dados, sequências, constraints, índices, triggers, FKs, views e rotinas sem erros relatados.

## Conferência no banco restaurado

```powershell
docker exec kairos-restore-test psql -U postgres -d kairos_restore -c "SELECT (SELECT COUNT(*) FROM users) AS usuarios, (SELECT COUNT(*) FROM employees) AS funcionarios, (SELECT COUNT(*) FROM products) AS produtos, (SELECT COUNT(*) FROM restockings) AS reposicoes, (SELECT COUNT(*) FROM companies) AS empresas;"

docker exec kairos-restore-test psql -U postgres -d kairos_restore -c "SELECT (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public') AS rotinas, (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema='public') AS eventos_de_triggers, (SELECT COUNT(*) FROM information_schema.views WHERE table_schema='public') AS views;"
```

| Verificação | Resultado observado |
|---|---:|
| `users` | 250.001 |
| `employees` | 50.001 |
| `products` | 80.000 |
| `restockings` | 50.000 |
| `companies` | 100 |
| Rotinas (functions + procedures) | 7 |
| Entradas de eventos em `information_schema.triggers` | 6 |
| Views | 11 |

**Nota:** as 6 entradas de `information_schema.triggers` são eventos das triggers, não necessariamente 6 triggers físicas. A listagem mostrou as triggers `trg_products_audit` e `trg_purchases_audit`.

## Critério de sucesso e limites
O teste de recuperação **passou**: `pg_restore` retornou 0 e a estrutura e os registros inspecionados estão presentes no ambiente isolado. Para evidência mais forte de equivalência, comparar as contagens com o banco de origem no mesmo período do backup, e opcionalmente executar verificações adicionais de integridade e consultas funcionais. O backup é um instantâneo do momento da execução, não um mecanismo automático de atualização ou recuperação contínua.

## Política sugerida (produção)
- Definir periodicidade de backups, retenção e local protegido de armazenamento.
- Restringir acesso ao backup, que pode conter dados pessoais ou hashes de senha.
- Testar restauração periodicamente em ambiente isolado e registrar data, versão, tamanho, checksum e resultado.
- Utilizar recursos de backup gerenciado da Aiven conforme plano e objetivos de recuperação (RPO/RTO).
- Em caso de falha, restaurar primeiro em ambiente de teste e validar antes de qualquer operação em produção.
- Credencial exposta durante testes anteriores deve ser rotacionada no painel da Aiven.

## Evidência de origem
Comandos e resultados registrados em 26/10/2026 no PowerShell do projeto, incluindo a inspeção `pg_restore -l`, a restauração `--exit-on-error --verbose` e o retorno `$LASTEXITCODE = 0`.
