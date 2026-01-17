<?php
/**
 * SQLMap 自动化扫描平台 - PHP 版本
 *
 * 主入口文件 - Web 界面 + API
 */

require_once __DIR__ . '/includes/Database.php';
require_once __DIR__ . '/includes/Task.php';

$config = require __DIR__ . '/config.php';

// 确保目录存在
if (!is_dir(__DIR__ . '/data')) mkdir(__DIR__ . '/data', 0755, true);
if (!is_dir($config['work_dir'])) mkdir($config['work_dir'], 0755, true);

// 路由处理
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

// API 路由
if (strpos($uri, '/api/') === 0) {
    header('Content-Type: application/json; charset=utf-8');

    $taskModel = new Task();
    $apiPath = substr($uri, 4); // 去掉 /api

    try {
        // GET /api/tasks - 获取任务列表
        if ($apiPath === '/tasks' && $method === 'GET') {
            $status = $_GET['status'] ?? null;
            $result = $taskModel->getList(50, 0, $status);
            echo json_encode($result, JSON_UNESCAPED_UNICODE);
            exit;
        }

        // POST /api/tasks - 创建任务
        if ($apiPath === '/tasks' && $method === 'POST') {
            $input = json_decode(file_get_contents('php://input'), true);
            $task = $taskModel->create($input);
            echo json_encode($task, JSON_UNESCAPED_UNICODE);
            exit;
        }

        // GET /api/tasks/{id} - 获取单个任务
        if (preg_match('#^/tasks/([a-f0-9-]+)$#', $apiPath, $matches) && $method === 'GET') {
            $task = $taskModel->get($matches[1]);
            if ($task) {
                echo json_encode($task, JSON_UNESCAPED_UNICODE);
            } else {
                http_response_code(404);
                echo json_encode(['error' => 'Task not found']);
            }
            exit;
        }

        // DELETE /api/tasks/{id} - 删除任务
        if (preg_match('#^/tasks/([a-f0-9-]+)$#', $apiPath, $matches) && $method === 'DELETE') {
            $taskModel->delete($matches[1]);
            echo json_encode(['ok' => true]);
            exit;
        }

        // GET /api/stats - 获取统计
        if ($apiPath === '/stats' && $method === 'GET') {
            echo json_encode($taskModel->getStats(), JSON_UNESCAPED_UNICODE);
            exit;
        }

        // POST /api/cleanup - 清理旧日志
        if ($apiPath === '/cleanup' && $method === 'POST') {
            $days = isset($_GET['days']) ? (int)$_GET['days'] : 7;
            $count = $taskModel->cleanup($days);
            echo json_encode(['ok' => true, 'deleted' => $count, 'days' => $days]);
            exit;
        }

        // 404
        http_response_code(404);
        echo json_encode(['error' => 'Not found']);
        exit;

    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(['error' => $e->getMessage()]);
        exit;
    }
}

// Web 界面
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SQLMap 自动化扫描平台</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0f0f23;
            color: #ccc;
            min-height: 100vh;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }

        header {
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 15px;
        }
        header h1 { color: #00d4ff; font-size: 24px; }

        .stats { display: flex; gap: 15px; flex-wrap: wrap; }
        .stat-item {
            text-align: center;
            padding: 10px 20px;
            background: rgba(255,255,255,0.05);
            border-radius: 8px;
        }
        .stat-value { font-size: 24px; font-weight: bold; }
        .stat-label { font-size: 12px; color: #888; }
        .stat-item.success .stat-value { color: #4caf50; }
        .stat-item.failed .stat-value { color: #f44336; }
        .stat-item.running .stat-value { color: #ff9800; }
        .stat-item.pending .stat-value { color: #2196f3; }

        .main-grid {
            display: grid;
            grid-template-columns: 400px 1fr;
            gap: 20px;
        }
        @media (max-width: 900px) {
            .main-grid { grid-template-columns: 1fr; }
        }

        .panel {
            background: #1a1a2e;
            border-radius: 10px;
            padding: 20px;
        }
        .panel h2 {
            color: #00d4ff;
            margin-bottom: 15px;
            font-size: 16px;
            padding-bottom: 10px;
            border-bottom: 1px solid #333;
        }

        .form-group { margin-bottom: 15px; }
        .form-group label {
            display: block;
            margin-bottom: 5px;
            color: #888;
            font-size: 13px;
        }
        .form-group input, .form-group textarea, .form-group select {
            width: 100%;
            padding: 10px;
            background: #0f0f23;
            border: 1px solid #333;
            border-radius: 5px;
            color: #fff;
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 13px;
        }
        .form-group textarea { min-height: 180px; resize: vertical; }
        .form-group input:focus, .form-group textarea:focus {
            border-color: #00d4ff;
            outline: none;
        }

        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            transition: all 0.3s;
        }
        .btn-primary {
            background: linear-gradient(135deg, #00d4ff 0%, #0099cc 100%);
            color: #000;
            width: 100%;
        }
        .btn-primary:hover { transform: translateY(-2px); box-shadow: 0 5px 20px rgba(0,212,255,0.3); }
        .btn-danger { background: #f44336; color: white; }
        .btn-sm { padding: 6px 12px; font-size: 12px; }

        .filter-tabs {
            display: flex;
            gap: 5px;
            margin-bottom: 15px;
            flex-wrap: wrap;
        }
        .filter-btn {
            padding: 6px 12px;
            background: #0f0f23;
            border: 1px solid #333;
            border-radius: 5px;
            color: #888;
            cursor: pointer;
            font-size: 12px;
            transition: all 0.2s;
        }
        .filter-btn:hover { border-color: #00d4ff; color: #00d4ff; }
        .filter-btn.active { background: #00d4ff; color: #000; border-color: #00d4ff; }

        .task-list { max-height: 500px; overflow-y: auto; }
        .task-item {
            background: #0f0f23;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 10px;
            cursor: pointer;
            transition: all 0.3s;
            border-left: 3px solid #333;
        }
        .task-item:hover { background: #16213e; }
        .task-item.success { border-left-color: #4caf50; }
        .task-item.failed { border-left-color: #f44336; }
        .task-item.running { border-left-color: #ff9800; }
        .task-item.pending { border-left-color: #2196f3; }

        .task-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
        }
        .task-name { font-weight: 500; color: #fff; }
        .task-status {
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 11px;
            text-transform: uppercase;
        }
        .task-status.success { background: #4caf50; color: #fff; }
        .task-status.failed { background: #f44336; color: #fff; }
        .task-status.running { background: #ff9800; color: #000; }
        .task-status.pending { background: #2196f3; color: #fff; }

        .task-target { font-size: 12px; color: #888; word-break: break-all; }
        .task-time { font-size: 11px; color: #666; margin-top: 5px; }
        .task-dbms {
            display: inline-block;
            background: #4caf50;
            color: #fff;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 10px;
            margin-top: 5px;
            margin-right: 5px;
        }
        .task-dba {
            display: inline-block;
            background: #ff5722;
            color: #fff;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 10px;
            margin-top: 5px;
            font-weight: bold;
        }

        .detail-panel { display: none; }
        .detail-panel.active { display: block; }

        .output-box {
            background: #0a0a15;
            border-radius: 5px;
            padding: 15px;
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 12px;
            line-height: 1.6;
            max-height: 400px;
            overflow-y: auto;
            white-space: pre-wrap;
            word-break: break-all;
        }

        .result-box {
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 15px;
        }
        .result-box.vulnerable {
            background: rgba(76, 175, 80, 0.2);
            border: 1px solid #4caf50;
        }
        .result-box.safe {
            background: rgba(244, 67, 54, 0.1);
            border: 1px solid #f44336;
        }

        .tabs { display: flex; gap: 10px; margin-bottom: 15px; }
        .tab {
            padding: 8px 16px;
            background: #0f0f23;
            border: none;
            border-radius: 5px;
            color: #888;
            cursor: pointer;
        }
        .tab.active { background: #00d4ff; color: #000; }

        .loading {
            display: inline-block;
            width: 16px;
            height: 16px;
            border: 2px solid #333;
            border-top-color: #00d4ff;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        .empty-state { text-align: center; padding: 40px; color: #666; }
        .worker-status {
            padding: 8px 15px;
            border-radius: 5px;
            font-size: 12px;
            margin-bottom: 15px;
        }
        .worker-status.running { background: rgba(76, 175, 80, 0.2); color: #4caf50; }
        .worker-status.stopped { background: rgba(244, 67, 54, 0.2); color: #f44336; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🔍 SQLMap 自动化扫描平台 <small style="font-size:12px;color:#666;">(PHP)</small></h1>
            <div class="stats">
                <div class="stat-item pending">
                    <div class="stat-value" id="stat-pending">0</div>
                    <div class="stat-label">等待中</div>
                </div>
                <div class="stat-item running">
                    <div class="stat-value" id="stat-running">0</div>
                    <div class="stat-label">运行中</div>
                </div>
                <div class="stat-item success">
                    <div class="stat-value" id="stat-success">0</div>
                    <div class="stat-label">发现漏洞</div>
                </div>
                <div class="stat-item failed">
                    <div class="stat-value" id="stat-failed">0</div>
                    <div class="stat-label">安全</div>
                </div>
            </div>
        </header>

        <div class="main-grid">
            <div class="left-col">
                <div class="panel">
                    <h2>📤 提交扫描任务</h2>
                    <form id="task-form">
                        <div class="form-group">
                            <label>任务名称 (可选)</label>
                            <input type="text" name="name" placeholder="留空自动生成">
                        </div>
                        <div class="form-group">
                            <label>HTTP 请求包</label>
                            <textarea name="request" placeholder="粘贴完整的 HTTP 请求包，例如:

GET /page.php?id=1 HTTP/1.1
Host: example.com
Cookie: session=abc123

或 POST 请求:

POST /login.php HTTP/1.1
Host: example.com
Content-Type: application/x-www-form-urlencoded

username=admin&password=123"></textarea>
                        </div>
                        <div class="form-group">
                            <label>额外 SQLMap 参数 (可选)</label>
                            <input type="text" name="options" placeholder="例如: --level=5 --risk=3 --dbs">
                        </div>
                        <button type="submit" class="btn btn-primary">🚀 开始扫描</button>
                    </form>
                </div>

                <div class="panel" style="margin-top: 20px;">
                    <h2>📋 任务列表</h2>
                    <div class="filter-tabs">
                        <button class="filter-btn active" data-filter="all">全部</button>
                        <button class="filter-btn" data-filter="success">有漏洞</button>
                        <button class="filter-btn" data-filter="failed">安全</button>
                        <button class="filter-btn" data-filter="running">运行中</button>
                        <button class="filter-btn" data-filter="pending">等待中</button>
                    </div>
                    <div class="task-list" id="task-list">
                        <div class="empty-state">暂无任务</div>
                    </div>
                </div>
            </div>

            <div class="right-col">
                <div class="panel detail-panel" id="detail-panel">
                    <h2>📊 任务详情 - <span id="detail-name"></span></h2>
                    <div class="result-box" id="result-box">
                        <div id="result-text"></div>
                    </div>
                    <div class="tabs">
                        <button class="tab active" data-tab="output">扫描输出</button>
                        <button class="tab" data-tab="request">请求详情</button>
                    </div>
                    <div class="tab-content" id="tab-output">
                        <div class="output-box" id="detail-output">等待扫描...</div>
                    </div>
                    <div class="tab-content" id="tab-request" style="display:none;">
                        <div class="output-box" id="detail-request"></div>
                    </div>
                    <div style="margin-top: 15px;">
                        <button class="btn btn-danger btn-sm" onclick="deleteTask()">🗑️ 删除任务</button>
                    </div>
                </div>

                <div class="panel" id="welcome-panel">
                    <h2>👋 欢迎使用</h2>
                    <div style="color: #888; line-height: 1.8;">
                        <p><strong>使用步骤:</strong></p>
                        <p>1. 启动 Worker: <code>php worker.php</code></p>
                        <p>2. 在左侧粘贴 HTTP 请求包</p>
                        <p>3. 点击"开始扫描"提交任务</p>
                        <p>4. Worker 会自动处理任务</p>
                        <br>
                        <p style="color: #ff9800;">⚠️ 仅用于授权的安全测试</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let currentTaskId = null;
        let currentFilter = 'all';
        let allTasks = [];

        async function loadStats() {
            const res = await fetch('/api/stats');
            const stats = await res.json();
            document.getElementById('stat-pending').textContent = stats.pending;
            document.getElementById('stat-running').textContent = stats.running;
            document.getElementById('stat-success').textContent = stats.success;
            document.getElementById('stat-failed').textContent = stats.failed;
        }

        async function loadTasks() {
            const res = await fetch('/api/tasks');
            const data = await res.json();
            allTasks = data.tasks || [];
            renderTasks();
        }

        function renderTasks() {
            const list = document.getElementById('task-list');
            let tasks = allTasks;

            if (currentFilter !== 'all') {
                tasks = allTasks.filter(t => t.status === currentFilter);
            }

            if (tasks.length === 0) {
                list.innerHTML = '<div class="empty-state">' +
                    (currentFilter === 'all' ? '暂无任务' : '没有符合条件的任务') + '</div>';
                return;
            }

            list.innerHTML = tasks.map(task => {
                const statusText = {pending: '等待中', running: '运行中', success: '有漏洞', failed: '安全'};
                let badges = '';
                if (task.dbms) badges += `<span class="task-dbms">${task.dbms}</span>`;
                if (task.is_dba === true) badges += `<span class="task-dba">DBA</span>`;

                return `
                    <div class="task-item ${task.status}" onclick="selectTask('${task.id}')">
                        <div class="task-header">
                            <span class="task-name">${task.name || 'Unnamed'}</span>
                            <span class="task-status ${task.status}">${statusText[task.status] || task.status}</span>
                        </div>
                        <div class="task-target">${task.target || 'N/A'}</div>
                        ${badges}
                        <div class="task-time">${new Date(task.created_at).toLocaleString()}</div>
                    </div>
                `;
            }).join('');
        }

        async function selectTask(id) {
            currentTaskId = id;
            const res = await fetch('/api/tasks/' + id);
            const task = await res.json();
            showTaskDetail(task);
            document.getElementById('welcome-panel').style.display = 'none';
            document.getElementById('detail-panel').classList.add('active');
        }

        function showTaskDetail(task) {
            document.getElementById('detail-name').textContent = task.name;
            document.getElementById('detail-output').textContent = task.output || '等待扫描输出...';
            document.getElementById('detail-request').textContent = task.request || '目标: ' + task.target;

            const resultBox = document.getElementById('result-box');
            const resultText = document.getElementById('result-text');

            if (task.status === 'success' && task.vulnerable) {
                resultBox.className = 'result-box vulnerable';
                let info = '🔴 <strong>发现 SQL 注入漏洞!</strong>';
                if (task.dbms) info += '<br>📦 数据库类型: <strong>' + task.dbms + '</strong>';
                if (task.is_dba === true) {
                    info += '<br>👑 <span style="color:#ff5722;font-weight:bold;">DBA 权限: 是</span>';
                } else if (task.is_dba === false) {
                    info += '<br>👤 DBA 权限: 否';
                }
                resultText.innerHTML = info;
            } else if (task.status === 'failed') {
                resultBox.className = 'result-box safe';
                resultText.innerHTML = '🟢 ' + (task.result || '未发现漏洞');
            } else if (task.status === 'running') {
                resultBox.className = 'result-box';
                resultBox.style.background = 'rgba(255, 152, 0, 0.2)';
                resultBox.style.border = '1px solid #ff9800';
                resultText.innerHTML = '⏳ 扫描进行中... <span class="loading"></span>';
            } else {
                resultBox.className = 'result-box';
                resultBox.style.background = 'rgba(33, 150, 243, 0.2)';
                resultBox.style.border = '1px solid #2196f3';
                resultText.innerHTML = '⏸️ 等待扫描...';
            }
        }

        async function deleteTask() {
            if (!currentTaskId || !confirm('确定删除此任务?')) return;
            await fetch('/api/tasks/' + currentTaskId, { method: 'DELETE' });
            currentTaskId = null;
            document.getElementById('detail-panel').classList.remove('active');
            document.getElementById('welcome-panel').style.display = 'block';
            loadTasks();
            loadStats();
        }

        document.getElementById('task-form').onsubmit = async (e) => {
            e.preventDefault();
            const form = e.target;
            const data = {
                name: form.name.value,
                request: form.request.value,
                options: form.options.value
            };

            if (!data.request.trim()) {
                alert('请输入 HTTP 请求包');
                return;
            }

            await fetch('/api/tasks', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            });

            form.reset();
            loadTasks();
            loadStats();
        };

        document.querySelectorAll('.tab').forEach(tab => {
            tab.onclick = () => {
                document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
                document.querySelectorAll('.tab-content').forEach(c => c.style.display = 'none');
                tab.classList.add('active');
                document.getElementById('tab-' + tab.dataset.tab).style.display = 'block';
            };
        });

        document.querySelectorAll('.filter-btn').forEach(btn => {
            btn.onclick = () => {
                document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentFilter = btn.dataset.filter;
                renderTasks();
            };
        });

        // 初始化
        loadStats();
        loadTasks();
        // 定时刷新
        setInterval(() => { loadStats(); loadTasks(); }, 3000);
    </script>
</body>
</html>
