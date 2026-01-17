<?php
/**
 * 数据库管理类
 */
class Database
{
    private static $instance = null;
    private $pdo;

    private function __construct($dbPath)
    {
        $dir = dirname($dbPath);
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }

        $this->pdo = new PDO("sqlite:$dbPath");
        $this->pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->initSchema();
    }

    public static function getInstance($dbPath = null)
    {
        if (self::$instance === null) {
            if ($dbPath === null) {
                $config = require __DIR__ . '/../config.php';
                $dbPath = $config['db_path'];
            }
            self::$instance = new self($dbPath);
        }
        return self::$instance;
    }

    public function getPdo()
    {
        return $this->pdo;
    }

    private function initSchema()
    {
        $this->pdo->exec("
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                name TEXT,
                request TEXT,
                target TEXT,
                method TEXT,
                data TEXT,
                cookies TEXT,
                headers TEXT,
                options TEXT,
                status TEXT DEFAULT 'pending',
                result TEXT,
                vulnerable INTEGER DEFAULT 0,
                dbms TEXT,
                is_dba INTEGER,
                log_file TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                started_at DATETIME,
                finished_at DATETIME
            );
            CREATE INDEX IF NOT EXISTS idx_status ON tasks(status);
            CREATE INDEX IF NOT EXISTS idx_created ON tasks(created_at);
        ");
    }
}
