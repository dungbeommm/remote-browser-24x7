from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]

class RepositoryTests(unittest.TestCase):
    def test_shell_syntax(self):
        files = [*ROOT.glob('app/*.sh'), *ROOT.glob('scripts/*.sh')]
        self.assertGreaterEqual(len(files), 4)
        for file in files:
            with self.subTest(file=file.name):
                subprocess.run(['bash', '-n', str(file)], check=True)

    def test_sensitive_files_not_committed(self):
        ignore = (ROOT / '.gitignore').read_text()
        self.assertIn('\n.env\n', '\n' + ignore)
        self.assertIn('backups/', ignore)
        self.assertIn('browser-data/', ignore)

    def test_auth_and_persistence_are_present(self):
        nginx = (ROOT / 'app/nginx.conf').read_text()
        compose = (ROOT / 'docker-compose.yml').read_text()
        self.assertIn('auth_basic_user_file', nginx)
        self.assertIn('127.0.0.1:${LOCAL_PORT:-8080}:8080', compose)
        self.assertIn('browser-data:/data', compose)
        self.assertIn('restart: unless-stopped', compose)

if __name__ == '__main__':
    unittest.main()
