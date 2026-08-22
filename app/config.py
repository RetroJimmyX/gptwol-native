import os

DATA_DIR = os.environ.get('GPTWOL_DATA_DIR', '/app/db')
SCHEDULE_FILE = os.environ.get('GPTWOL_SCHEDULE_FILE', '/etc/cron.d/gptwol')
LEGACY_COMPUTERS_FILE = os.path.join(DATA_DIR, 'computers.txt')
DATABASE_FILE = os.path.join(DATA_DIR, 'computers.db')

os.makedirs(DATA_DIR, exist_ok=True)
