<?php
/**
 * 任务管理类
 */
class Task
{
    private $db;

    public function __construct()
    {
        $this->db = Database::getInstance()->getPdo();
    }

    /**
     * 生成 UUID
     */
    private function generateUUID()
    {
        return sprintf(
            '%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
            mt_rand(0, 0xffff), mt_rand(0, 0xffff),
            mt_rand(0, 0xffff),
            mt_rand(0, 0x0fff) | 0x4000,
            mt_rand(0, 0x3fff) | 0x8000,
            mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
        );
    }

    /**
     * 解析 HTTP 请求包
     */
    public function parseRequest($raw)
    {
        $result = [
            'target' => '',
            'method' => 'GET',
            'data' => '',
            'cookies' => '',
            'headers' => ''
        ];

        $lines = preg_split('/\r?\n/', $raw);
        if (empty($lines)) return $result;

        // 解析请求行
        $parts = preg_split('/\s+/', $lines[0]);
        if (count($parts) >= 2) {
            $result['method'] = $parts[0];
            $path = $parts[1];
        } else {
            return $result;
        }

        $headerLines = [];
        $host = '';
        $inBody = false;
        $body = '';

        for ($i = 1; $i < count($lines); $i++) {
            $line = $lines[$i];

            if ($line === '') {
                $inBody = true;
                continue;
            }

            if ($inBody) {
                $body .= $line . "\n";
            } else {
                $headerLines[] = $line;
                if (stripos($line, 'host:') === 0) {
                    $host = trim(substr($line, 5));
                } elseif (stripos($line, 'cookie:') === 0) {
                    $result['cookies'] = trim(substr($line, 7));
                }
            }
        }

        // 构建目标 URL
        if ($host && isset($path)) {
            $scheme = 'http';
            if (strpos($raw, ':443') !== false || stripos($raw, 'https') !== false) {
                $scheme = 'https';
            }
            $result['target'] = "$scheme://$host$path";
        }

        $result['data'] = trim($body);
        $result['headers'] = implode("\n", $headerLines);

        return $result;
    }

    /**
     * 创建任务
     */
    public function create($data)
    {
        $id = $this->generateUUID();

        // 如果提供了原始请求包，解析它
        if (!empty($data['request'])) {
            $parsed = $this->parseRequest($data['request']);
            $data = array_merge($parsed, $data);
        }

        $name = $data['name'] ?? 'Task-' . date('md-His');

        $stmt = $this->db->prepare("
            INSERT INTO tasks (id, name, request, target, method, data, cookies, headers, options, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'))
        ");

        $stmt->execute([
            $id,
            $name,
            $data['request'] ?? '',
            $data['target'] ?? '',
            $data['method'] ?? 'GET',
            $data['data'] ?? '',
            $data['cookies'] ?? '',
            $data['headers'] ?? '',
            $data['options'] ?? ''
        ]);

        return $this->get($id);
    }

    /**
     * 获取单个任务
     */
    public function get($id)
    {
        $stmt = $this->db->prepare("SELECT * FROM tasks WHERE id = ?");
        $stmt->execute([$id]);
        $task = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($task) {
            $task['vulnerable'] = (bool)$task['vulnerable'];
            $task['is_dba'] = $task['is_dba'] === null ? null : (bool)$task['is_dba'];

            // 从日志文件读取输出
            if (!empty($task['log_file']) && file_exists($task['log_file'])) {
                $task['output'] = file_get_contents($task['log_file']);
            } else {
                $task['output'] = '';
            }
        }

        return $task;
    }

    /**
     * 获取任务列表
     */
    public function getList($limit = 50, $offset = 0, $status = null)
    {
        $sql = "SELECT * FROM tasks";
        $params = [];

        if ($status && $status !== 'all') {
            $sql .= " WHERE status = ?";
            $params[] = $status;
        }

        $sql .= " ORDER BY created_at DESC LIMIT ? OFFSET ?";
        $params[] = $limit;
        $params[] = $offset;

        $stmt = $this->db->prepare($sql);
        $stmt->execute($params);
        $tasks = $stmt->fetchAll(PDO::FETCH_ASSOC);

        foreach ($tasks as &$task) {
            $task['vulnerable'] = (bool)$task['vulnerable'];
            $task['is_dba'] = $task['is_dba'] === null ? null : (bool)$task['is_dba'];
        }

        // 获取总数
        $countSql = "SELECT COUNT(*) FROM tasks";
        if ($status && $status !== 'all') {
            $countSql .= " WHERE status = ?";
            $total = $this->db->prepare($countSql);
            $total->execute([$status]);
        } else {
            $total = $this->db->query($countSql);
        }

        return [
            'tasks' => $tasks,
            'total' => (int)$total->fetchColumn()
        ];
    }

    /**
     * 更新任务
     */
    public function update($id, $data)
    {
        $fields = [];
        $params = [];

        foreach ($data as $key => $value) {
            if ($key === 'id') continue;
            $fields[] = "$key = ?";
            $params[] = $value;
        }

        $params[] = $id;

        $stmt = $this->db->prepare("UPDATE tasks SET " . implode(', ', $fields) . " WHERE id = ?");
        $stmt->execute($params);

        return $this->get($id);
    }

    /**
     * 删除任务及其日志文件
     */
    public function delete($id)
    {
        // 先获取日志文件路径
        $task = $this->get($id);
        if ($task && !empty($task['log_file']) && file_exists($task['log_file'])) {
            unlink($task['log_file']);
        }

        $stmt = $this->db->prepare("DELETE FROM tasks WHERE id = ?");
        return $stmt->execute([$id]);
    }

    /**
     * 清理指定天数之前的任务和日志
     */
    public function cleanup($days = 7)
    {
        $cutoff = date('Y-m-d H:i:s', strtotime("-$days days"));

        // 获取旧任务
        $stmt = $this->db->prepare("
            SELECT id, log_file FROM tasks
            WHERE finished_at < ? AND log_file IS NOT NULL
        ");
        $stmt->execute([$cutoff]);
        $tasks = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $count = 0;
        foreach ($tasks as $task) {
            if (!empty($task['log_file']) && file_exists($task['log_file'])) {
                unlink($task['log_file']);
            }
            $this->db->exec("DELETE FROM tasks WHERE id = '{$task['id']}'");
            $count++;
        }

        // 清理空的日期目录
        $config = require __DIR__ . '/../config.php';
        $logsDir = $config['work_dir'] . '/logs';
        if (is_dir($logsDir)) {
            foreach (scandir($logsDir) as $entry) {
                if ($entry === '.' || $entry === '..') continue;
                $dirPath = "$logsDir/$entry";
                if (is_dir($dirPath)) {
                    $files = array_diff(scandir($dirPath), ['.', '..']);
                    if (empty($files)) {
                        rmdir($dirPath);
                    }
                }
            }
        }

        return $count;
    }

    /**
     * 获取待处理任务
     */
    public function getPending($limit = 1)
    {
        $stmt = $this->db->prepare("
            SELECT * FROM tasks
            WHERE status = 'pending'
            ORDER BY created_at ASC
            LIMIT ?
        ");
        $stmt->execute([$limit]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    /**
     * 获取统计信息
     */
    public function getStats()
    {
        $stats = [
            'pending' => 0,
            'running' => 0,
            'success' => 0,
            'failed' => 0,
            'total' => 0
        ];

        $result = $this->db->query("
            SELECT status, COUNT(*) as count
            FROM tasks
            GROUP BY status
        ");

        while ($row = $result->fetch(PDO::FETCH_ASSOC)) {
            $stats[$row['status']] = (int)$row['count'];
            $stats['total'] += (int)$row['count'];
        }

        return $stats;
    }

    /**
     * 获取正在运行的任务数
     */
    public function getRunningCount()
    {
        $stmt = $this->db->query("SELECT COUNT(*) FROM tasks WHERE status = 'running'");
        return (int)$stmt->fetchColumn();
    }
}
