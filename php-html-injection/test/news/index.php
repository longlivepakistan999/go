<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>新闻 - 测试页面</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 80px 20px; }
        .article { background: #fff; padding: 20px; margin: 10px 0; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <h1>📰 新闻页面</h1>
    <p>路径: <code><?php echo $_SERVER['REQUEST_URI']; ?></code></p>

    <div class="article">
        <h2>新闻标题 1</h2>
        <p>这是一条新闻内容...</p>
    </div>

    <div class="article">
        <h2>新闻标题 2</h2>
        <p>这是另一条新闻内容...</p>
    </div>

    <p><a href="/">← 返回首页</a></p>
</body>
</html>
