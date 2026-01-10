<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>测试页面</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 80px 20px 20px;
            background: #f5f5f5;
        }
        .card {
            background: white;
            border-radius: 8px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
            margin-top: 0;
        }
        .info {
            background: #e3f2fd;
            padding: 15px;
            border-radius: 4px;
            margin: 15px 0;
        }
        .success {
            background: #e8f5e9;
            color: #2e7d32;
            padding: 15px;
            border-radius: 4px;
        }
        code {
            background: #f5f5f5;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Monaco', 'Consolas', monospace;
        }
        a {
            color: #1976d2;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>🎉 HTML 注入测试</h1>

        <div class="success">
            <strong>✅ 如果您在页面顶部看到了所有者横幅，说明注入成功！</strong>
        </div>

        <div class="info">
            <strong>服务器信息:</strong><br>
            PHP 版本: <?php echo phpversion(); ?><br>
            当前时间: <?php echo date('Y-m-d H:i:s'); ?><br>
            请求路径: <?php echo $_SERVER['REQUEST_URI']; ?>
        </div>

        <h2>测试链接</h2>
        <ul>
            <li><a href="/">首页</a></li>
            <li><a href="/news/">新闻页面</a> (如果配置了路径过滤)</li>
            <li><a href="/about.php">关于页面</a></li>
            <li><a href="/api/test.json">API 接口</a> (不会注入)</li>
        </ul>
    </div>

    <div class="card">
        <h2>使用说明</h2>
        <p>启动命令示例:</p>
        <pre><code># 基本启动
./start.sh

# 指定所有者
./start.sh -o "我的公司"

# 只注入 /news/ 路径
./start.sh -P "/news/" -o "我的公司"

# 调试模式
./start.sh -d</code></pre>
    </div>
</body>
</html>
