"""Measured SELECT plans on a dedicated local database; index DDL is rolled back."""
import argparse
import json
import statistics
from pathlib import Path

import psycopg


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--authorize-local', action='store_true')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not args.authorize_local:
        raise SystemExit('Explicit --authorize-local required')
    with psycopg.connect(host='127.0.0.1', dbname='kairos_modelagem_test', user='postgres',
                         autocommit=True, connect_timeout=5) as db:
        if db.execute('SELECT current_database()').fetchone()[0] != 'kairos_modelagem_test':
            raise SystemExit('Dedicated local database required')
        indexes = lambda: db.execute("SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY indexname").fetchall()
        original = indexes()
        employee = db.execute('SELECT employee_id FROM restockings GROUP BY employee_id ORDER BY count(*) DESC,employee_id LIMIT 1').fetchone()[0]
        alert_employee = db.execute("SELECT employee_id FROM alerts WHERE status='OPEN' GROUP BY employee_id ORDER BY count(*) DESC,employee_id LIMIT 1").fetchone()[0]
        queries = {
            'restockings': f'SELECT id,employee_id,product_id,restocking_date FROM restockings WHERE employee_id={employee} ORDER BY restocking_date DESC LIMIT 25',
            'open_alerts': f"SELECT id,employee_id,shelf_id,stockout_date FROM alerts WHERE employee_id={alert_employee} AND status='OPEN' ORDER BY stockout_date DESC LIMIT 25",
            'product_inventory': 'SELECT inventory_id,product_id,product_quantity FROM product_inventories WHERE product_id=1',
            'customer_purchases': 'SELECT id,date,status FROM purchases WHERE customer_id=1 ORDER BY date DESC LIMIT 25'
        }
        definitions = {
            'idx_restockings_employee_date': 'restockings(employee_id,restocking_date DESC)',
            'idx_alerts_open_employee_date': "alerts(employee_id,stockout_date DESC) WHERE status='OPEN'",
            'idx_product_inventories_product': 'product_inventories(product_id)',
            'idx_purchases_customer_date': 'purchases(customer_id,date DESC)'
        }
        report = {'server_version': db.execute('SHOW server_version').fetchone()[0], 'runs': 7,
                  'warmups': 2, 'indexes_before': original, 'queries': {}, 'index_definitions': definitions}
        tables = db.execute("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename").fetchall()
        from psycopg import sql
        report['row_counts'] = {name: db.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier(name))).fetchone()[0]
                                for (name,) in tables}
        db.execute('BEGIN')
        expected_results = {}
        try:
            for name in definitions:
                db.execute(sql.SQL('DROP INDEX IF EXISTS {}').format(sql.Identifier(name)))
            db.execute('ANALYZE')
            for stage in ('before', 'after'):
                if stage == 'after':
                    for name, definition in definitions.items():
                        db.execute(f'CREATE INDEX {name} ON {definition}')  # Fixed definitions, not user SQL.
                for name, query in queries.items():
                    actual_results = sorted(db.execute(query).fetchall(), key=str)
                    if stage == 'before':
                        expected_results[name] = actual_results
                    elif actual_results != expected_results[name]:
                        raise RuntimeError('Different query results after index')
                    plans = [db.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + query).fetchone()[0][0]
                             for _ in range(9)]
                    measured = plans[2:]
                    report['queries'].setdefault(name, {'sql': query})[stage] = {
                        'median_ms': statistics.median(p['Execution Time'] for p in measured),
                        'execution_ms': [p['Execution Time'] for p in measured], 'representative_plan': measured[3],
                        'rows': measured[3]['Plan']['Actual Rows']}
                    report['queries'][name]['results_equal'] = True
                    if stage == 'after':
                        if report['queries'][name]['before']['rows'] != measured[3]['Plan']['Actual Rows']:
                            raise RuntimeError('Different row count after index')
            report['indexes_during_test'] = indexes()
        finally:
            db.execute('ROLLBACK')
        report['indexes_after_rollback'] = indexes()
        if report['indexes_after_rollback'] != original:
            raise RuntimeError('Index state was not restored')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps({name: {s: data[s]['median_ms'] for s in ('before', 'after')}
                          for name, data in report['queries'].items()}, indent=2))


if __name__ == '__main__':
    main()
