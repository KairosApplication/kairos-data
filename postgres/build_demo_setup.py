"""Build a pgAdmin-compatible setup from existing SQL; never connects to a DB."""
import argparse
from pathlib import Path


def build_setup():
    sql_dir = Path(__file__).resolve().parent
    guard = """
DO $$
BEGIN
    IF current_database() <> 'kairos_demo' THEN
        RAISE EXCEPTION 'Abra o Query Tool de kairos_demo; banco atual: %', current_database();
    END IF;
END $$;
"""
    empty = """
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
               WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S','f')) THEN
        RAISE EXCEPTION 'kairos_demo deve estar vazio. Nao recarregue uma base existente.';
    END IF;
END $$;
"""
    # A single transaction includes schema, routines and seed. Remove only the
    # seed's outer transaction markers; do not alter its business SQL.
    seed = (sql_dir / 'ScriptSQL_Kairos_Dataload_1M.sql').read_text(encoding='utf-8-sig')
    assert seed.count('\nBEGIN;') == 1 and seed.count('\nCOMMIT;') == 1
    seed = seed.replace('\nBEGIN;', '\n', 1).replace('\nCOMMIT;', '\n', 1)
    parts = ['-- GENERATED: executar inteiro em kairos_demo VAZIO.\nBEGIN;', guard, empty,
             "SET LOCAL TIME ZONE 'America/Sao_Paulo';"]
    for name in ('ScriptSQL_Kairos_Criacao_Tabelas.sql',
                 'ScriptSQL_Kairos_Triggers_Procedures_Functions.sql'):
        parts.append((sql_dir / name).read_text(encoding='utf-8-sig'))
    parts += [seed, 'COMMIT;']
    for name in ('ScriptSQL_Kairos_bi_views.sql', 'ScriptSQL_Kairos_Demo_KPIs.sql'):
        parts += ['BEGIN;', guard, (sql_dir / name).read_text(encoding='utf-8-sig'), 'COMMIT;']
    parts += ["SET kairos.demo_authorized_database = 'kairos_demo';",
              (sql_dir / 'ScriptSQL_Kairos_Demo_Datas.sql').read_text(encoding='utf-8-sig'),
              'ANALYZE;',
              (sql_dir / 'ScriptSQL_Kairos_Demo_Validation.sql').read_text(encoding='utf-8-sig'),
              (sql_dir / 'ScriptSQL_Kairos_model_validation.sql').read_text(encoding='utf-8-sig')]
    return '\n\n'.join(parts) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    # Exclusive creation: never overwrite an existing file.
    with args.output.open('x', encoding='utf-8') as output:
        output.write(build_setup())
    print(f'Abra no pgAdmin: {args.output.resolve()}')
