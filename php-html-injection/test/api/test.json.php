<?php
header('Content-Type: application/json');
echo json_encode([
    'status' => 'ok',
    'message' => '这是 API 接口，不会被注入 HTML',
    'time' => date('Y-m-d H:i:s')
], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
