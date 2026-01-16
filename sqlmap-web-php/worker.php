#!/usr/bin/env php
<?php
/**
 * SQLMap Worker - 后台任务处理
 *
 * 用法:
 *   php worker.php          # 前台运行
 *   php worker.php daemon   # 后台运行
 *   php worker.php stop     # 停止后台进程
 */

require_once __DIR__ . '/includes/Database.php';
require_once __DIR__ . '/includes/Task.php';

$config = require __DIR__ . '/config.php';

// PID 文件
$pidFile = __DIR__ . '/data/worker.pid';

/**
 * 写入日志
 */
function logMsg($msg)
{
    $time = date('Y-m-d H:i:s');
    echo "[$time] $msg\n";
    file_put_contents(__DIR__ . '/data/worker.log', "[$time] $msg\n", FILE_APPEND);
}

/**
 * 处理单个任务
 */
function processTask($task, $config)
{
    $taskModel = new Task();

    logMsg("[Task {$task['id']}] 开始扫描: {$task['target']}");

    // 更新状态为运行中
    $taskModel->update($task['id'], [
        'status' => 'running',
        'started_at' => date('Y-m-d H:i:s')
    ]);

    // 准备请求文件
    $reqFile = null;
    if (!empty($task['request'])) {
        $reqFile = $config['work_dir'] . '/' . $task['id'] . '.req';
        file_put_contents($reqFile, $task['request']);
    }

    // 构建 SQLMap 命令
    $args = $config['default_args'];
    $args[] = '--output-dir=' . $config['work_dir'];

    if ($reqFile) {
        $args[] = '-r';
        $args[] = $reqFile;
    } else {
        $args[] = '-u';
        $args[] = $task['target'];
        if ($task['method'] === 'POST' && !empty($task['data'])) {
            $args[] = '--data';
            $args[] = $task['data'];
        }
    }

    if (!empty($task['cookies'])) {
        $args[] = '--cookie';
        $args[] = $task['cookies'];
    }

    // 额外参数
    if (!empty($task['options'])) {
        $extraArgs = preg_split('/\s+/', $task['options']);
        $args = array_merge($args, $extraArgs);
    }

    // 构建命令
    $cmd = escapeshellcmd($config['sqlmap_path']);
    foreach ($args as $arg) {
        $cmd .= ' ' . escapeshellarg($arg);
    }
    $cmd .= ' 2>&1';

    logMsg("[Task {$task['id']}] 执行命令: $cmd");

    // 执行 SQLMap
    $output = [];
    $returnCode = 0;
    exec($cmd, $output, $returnCode);
    $outputStr = implode("\n", $output);

    // 清理请求文件
    if ($reqFile && file_exists($reqFile)) {
        unlink($reqFile);
    }

    // 分析结果
    $result = [
        'output' => $outputStr,
        'finished_at' => date('Y-m-d H:i:s'),
        'status' => 'failed',
        'vulnerable' => 0,
        'result' => '扫描完成，无明确结果',
        'dbms' => null,
        'is_dba' => null
    ];

    // 检测是否发现漏洞
    if (
        strpos($outputStr, 'is vulnerable') !== false ||
        strpos($outputStr, 'sqlmap identified the following injection') !== false ||
        (strpos($outputStr, 'Parameter:') !== false && strpos($outputStr, 'Type:') !== false)
    ) {
        $result['status'] = 'success';
        $result['vulnerable'] = 1;
        $result['result'] = '发现 SQL 注入漏洞!';

        // 提取数据库类型
        if (preg_match('/back-end DBMS:\s*(.+)$/m', $outputStr, $matches)) {
            $result['dbms'] = trim($matches[1]);
        }

        // 检测是否为 DBA
        if (strpos($outputStr, 'current user is DBA: True') !== false) {
            $result['is_dba'] = 1;
        } elseif (strpos($outputStr, 'current user is DBA: False') !== false) {
            $result['is_dba'] = 0;
        }

        logMsg("[Task {$task['id']}] 发现漏洞! DBMS: {$result['dbms']}, DBA: " . ($result['is_dba'] ? '是' : '否'));
    } elseif (strpos($outputStr, 'all tested parameters do not appear to be injectable') !== false) {
        $result['status'] = 'failed';
        $result['vulnerable'] = 0;
        $result['result'] = '未发现 SQL 注入漏洞';
        logMsg("[Task {$task['id']}] 未发现漏洞");
    }

    // 更新任务
    $taskModel->update($task['id'], $result);

    logMsg("[Task {$task['id']}] 完成: {$result['status']}");
}

/**
 * 主循环
 */
function mainLoop($config)
{
    logMsg("Worker 启动，最大并发: {$config['max_workers']}");

    // 确保工作目录存在
    if (!is_dir($config['work_dir'])) {
        mkdir($config['work_dir'], 0755, true);
    }

    $taskModel = new Task();
    $children = [];

    while (true) {
        // 清理已完成的子进程
        foreach ($children as $pid => $taskId) {
            $status = null;
            $res = pcntl_waitpid($pid, $status, WNOHANG);
            if ($res == -1 || $res > 0) {
                unset($children[$pid]);
            }
        }

        // 检查是否可以启动新任务
        $runningCount = count($children);

        if ($runningCount < $config['max_workers']) {
            $tasks = $taskModel->getPending($config['max_workers'] - $runningCount);

            foreach ($tasks as $task) {
                // Fork 子进程处理任务
                $pid = pcntl_fork();

                if ($pid == -1) {
                    logMsg("无法创建子进程");
                } elseif ($pid == 0) {
                    // 子进程
                    try {
                        processTask($task, $config);
                    } catch (Exception $e) {
                        logMsg("任务执行错误: " . $e->getMessage());
                    }
                    exit(0);
                } else {
                    // 父进程
                    $children[$pid] = $task['id'];
                    logMsg("启动任务 {$task['id']} (PID: $pid)");
                }
            }
        }

        // 等待一秒
        sleep(1);
    }
}

/**
 * 无 pcntl 的简化版本
 */
function mainLoopSimple($config)
{
    logMsg("Worker 启动 (单进程模式)");

    if (!is_dir($config['work_dir'])) {
        mkdir($config['work_dir'], 0755, true);
    }

    $taskModel = new Task();

    while (true) {
        $tasks = $taskModel->getPending(1);

        if (!empty($tasks)) {
            try {
                processTask($tasks[0], $config);
            } catch (Exception $e) {
                logMsg("任务执行错误: " . $e->getMessage());
            }
        }

        sleep(1);
    }
}

// 确保数据目录存在
if (!is_dir(__DIR__ . '/data')) {
    mkdir(__DIR__ . '/data', 0755, true);
}

// 命令行参数处理
$action = $argv[1] ?? 'run';

switch ($action) {
    case 'daemon':
        // 后台运行
        if (!function_exists('pcntl_fork')) {
            die("需要 pcntl 扩展才能后台运行\n");
        }

        $pid = pcntl_fork();
        if ($pid == -1) {
            die("无法创建守护进程\n");
        } elseif ($pid > 0) {
            // 父进程
            file_put_contents($pidFile, $pid);
            echo "Worker 已启动 (PID: $pid)\n";
            exit(0);
        }

        // 子进程
        posix_setsid();
        mainLoop($config);
        break;

    case 'stop':
        if (file_exists($pidFile)) {
            $pid = (int)file_get_contents($pidFile);
            if ($pid > 0) {
                posix_kill($pid, SIGTERM);
                unlink($pidFile);
                echo "Worker 已停止 (PID: $pid)\n";
            }
        } else {
            echo "Worker 未运行\n";
        }
        break;

    case 'status':
        if (file_exists($pidFile)) {
            $pid = (int)file_get_contents($pidFile);
            if ($pid > 0 && posix_kill($pid, 0)) {
                echo "Worker 运行中 (PID: $pid)\n";
            } else {
                echo "Worker 已停止\n";
                unlink($pidFile);
            }
        } else {
            echo "Worker 未运行\n";
        }
        break;

    default:
        // 前台运行
        logMsg("按 Ctrl+C 停止");
        if (function_exists('pcntl_fork')) {
            mainLoop($config);
        } else {
            mainLoopSimple($config);
        }
        break;
}
