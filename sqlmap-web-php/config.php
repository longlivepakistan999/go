<?php
/**
 * SQLMap 自动化扫描平台 - PHP 版本
 *
 * 配置文件
 */

return [
    // 数据库路径
    'db_path' => __DIR__ . '/data/sqlmap.db',

    // SQLMap 路径
    'sqlmap_path' => 'sqlmap',

    // 工作目录
    'work_dir' => __DIR__ . '/output',

    // 最大并发数
    'max_workers' => 2,

    // 默认 SQLMap 参数
    'default_args' => [
        '--batch',
        '--flush-session',
        '--is-dba',
    ],
];
