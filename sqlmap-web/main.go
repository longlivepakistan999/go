package main

import (
	"bufio"
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	_ "github.com/mattn/go-sqlite3"
)

// Task 表示一个 SQLMap 扫描任务
type Task struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Request     string    `json:"request"`      // HTTP 请求包
	Target      string    `json:"target"`       // 目标 URL
	Method      string    `json:"method"`       // GET/POST
	Data        string    `json:"data"`         // POST 数据
	Cookies     string    `json:"cookies"`      // Cookies
	Headers     string    `json:"headers"`      // 自定义 Headers
	Options     string    `json:"options"`      // 额外 SQLMap 参数
	Status      string    `json:"status"`       // pending/running/success/failed
	Result      string    `json:"result"`       // 扫描结果
	Output      string    `json:"output"`       // 完整输出
	Vulnerable  bool      `json:"vulnerable"`   // 是否存在漏洞
	DBMS        string    `json:"dbms"`         // 数据库类型
	IsDBA       *bool     `json:"is_dba"`       // 是否为 DBA
	LogFile     string    `json:"log_file"`     // 日志文件路径
	CreatedAt   time.Time `json:"created_at"`
	StartedAt   *time.Time `json:"started_at"`
	FinishedAt  *time.Time `json:"finished_at"`
}

// App 应用主结构
type App struct {
	db          *sql.DB
	sqlmapPath  string
	workDir     string
	maxWorkers  int
	taskChan    chan string
	wsClients   map[*websocket.Conn]bool
	wsLock      sync.RWMutex
	upgrader    websocket.Upgrader
}

// NewApp 创建应用实例
func NewApp(dbPath, sqlmapPath, workDir string, maxWorkers int) (*App, error) {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, err
	}

	app := &App{
		db:         db,
		sqlmapPath: sqlmapPath,
		workDir:    workDir,
		maxWorkers: maxWorkers,
		taskChan:   make(chan string, 100),
		wsClients:  make(map[*websocket.Conn]bool),
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	}

	if err := app.initDB(); err != nil {
		return nil, err
	}

	// 创建工作目录
	os.MkdirAll(workDir, 0755)

	return app, nil
}

// initDB 初始化数据库表
func (app *App) initDB() error {
	schema := `
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
		output TEXT,
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
	`
	_, err := app.db.Exec(schema)
	return err
}

// CreateTask 创建新任务
func (app *App) CreateTask(task *Task) error {
	task.ID = uuid.New().String()
	task.Status = "pending"
	task.CreatedAt = time.Now()

	_, err := app.db.Exec(`
		INSERT INTO tasks (id, name, request, target, method, data, cookies, headers, options, status, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, task.ID, task.Name, task.Request, task.Target, task.Method, task.Data, task.Cookies, task.Headers, task.Options, task.Status, task.CreatedAt)

	if err == nil {
		// 添加到任务队列
		app.taskChan <- task.ID
	}

	return err
}

// GetTask 获取任务详情
func (app *App) GetTask(id string) (*Task, error) {
	task := &Task{}
	var startedAt, finishedAt sql.NullTime
	var vulnerable int
	var isDBA sql.NullInt64
	var logFile sql.NullString

	err := app.db.QueryRow(`
		SELECT id, name, request, target, method, data, cookies, headers, options,
		       status, COALESCE(result,''), vulnerable, COALESCE(dbms,''),
		       is_dba, COALESCE(log_file,''), created_at, started_at, finished_at
		FROM tasks WHERE id = ?
	`, id).Scan(
		&task.ID, &task.Name, &task.Request, &task.Target, &task.Method,
		&task.Data, &task.Cookies, &task.Headers, &task.Options,
		&task.Status, &task.Result, &vulnerable, &task.DBMS,
		&isDBA, &logFile, &task.CreatedAt, &startedAt, &finishedAt,
	)

	if err != nil {
		return nil, err
	}

	task.Vulnerable = vulnerable == 1
	if isDBA.Valid {
		val := isDBA.Int64 == 1
		task.IsDBA = &val
	}
	if logFile.Valid {
		task.LogFile = logFile.String
		// 从文件读取输出日志
		if content, err := os.ReadFile(task.LogFile); err == nil {
			task.Output = string(content)
		}
	}
	if startedAt.Valid {
		task.StartedAt = &startedAt.Time
	}
	if finishedAt.Valid {
		task.FinishedAt = &finishedAt.Time
	}

	return task, nil
}

// GetTasks 获取任务列表
func (app *App) GetTasks(limit, offset int) ([]*Task, int, error) {
	var total int
	app.db.QueryRow("SELECT COUNT(*) FROM tasks").Scan(&total)

	rows, err := app.db.Query(`
		SELECT id, name, target, method, status, vulnerable, COALESCE(dbms,''), is_dba, COALESCE(log_file,''), created_at, finished_at
		FROM tasks ORDER BY created_at DESC LIMIT ? OFFSET ?
	`, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var tasks []*Task
	for rows.Next() {
		task := &Task{}
		var finishedAt sql.NullTime
		var vulnerable int
		var isDBA sql.NullInt64
		var logFile sql.NullString

		err := rows.Scan(&task.ID, &task.Name, &task.Target, &task.Method,
			&task.Status, &vulnerable, &task.DBMS, &isDBA, &logFile, &task.CreatedAt, &finishedAt)
		if err != nil {
			continue
		}

		task.Vulnerable = vulnerable == 1
		if isDBA.Valid {
			val := isDBA.Int64 == 1
			task.IsDBA = &val
		}
		if logFile.Valid {
			task.LogFile = logFile.String
		}
		if finishedAt.Valid {
			task.FinishedAt = &finishedAt.Time
		}
		tasks = append(tasks, task)
	}

	return tasks, total, nil
}

// UpdateTask 更新任务状态
func (app *App) UpdateTask(task *Task) error {
	vulnerable := 0
	if task.Vulnerable {
		vulnerable = 1
	}

	var isDBA *int
	if task.IsDBA != nil {
		val := 0
		if *task.IsDBA {
			val = 1
		}
		isDBA = &val
	}

	_, err := app.db.Exec(`
		UPDATE tasks SET status=?, result=?, vulnerable=?, dbms=?, is_dba=?, log_file=?,
		                 started_at=?, finished_at=?
		WHERE id=?
	`, task.Status, task.Result, vulnerable, task.DBMS, isDBA, task.LogFile,
		task.StartedAt, task.FinishedAt, task.ID)

	return err
}

// DeleteTask 删除任务及其日志文件
func (app *App) DeleteTask(id string) error {
	// 先获取日志文件路径
	task, _ := app.GetTask(id)
	if task != nil && task.LogFile != "" {
		os.Remove(task.LogFile)
	}

	_, err := app.db.Exec("DELETE FROM tasks WHERE id=?", id)
	return err
}

// CleanupOldLogs 清理指定天数之前的日志
func (app *App) CleanupOldLogs(days int) (int, error) {
	cutoff := time.Now().AddDate(0, 0, -days)

	// 获取旧任务
	rows, err := app.db.Query(`
		SELECT id, log_file FROM tasks
		WHERE finished_at < ? AND log_file IS NOT NULL
	`, cutoff)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	count := 0
	for rows.Next() {
		var id, logFile string
		rows.Scan(&id, &logFile)
		if logFile != "" {
			os.Remove(logFile)
		}
		app.db.Exec("DELETE FROM tasks WHERE id=?", id)
		count++
	}

	// 清理空的日期目录
	logsDir := filepath.Join(app.workDir, "logs")
	entries, _ := os.ReadDir(logsDir)
	for _, entry := range entries {
		if entry.IsDir() {
			dirPath := filepath.Join(logsDir, entry.Name())
			subEntries, _ := os.ReadDir(dirPath)
			if len(subEntries) == 0 {
				os.Remove(dirPath)
			}
		}
	}

	return count, nil
}

// ParseRequest 解析 HTTP 请求包
func ParseRequest(raw string) (target, method, data, cookies, headers string) {
	lines := strings.Split(strings.ReplaceAll(raw, "\r\n", "\n"), "\n")
	if len(lines) == 0 {
		return
	}

	// 解析请求行
	parts := strings.Fields(lines[0])
	if len(parts) >= 2 {
		method = parts[0]
	}

	var headerLines []string
	var host string
	inBody := false

	for i := 1; i < len(lines); i++ {
		line := lines[i]

		if line == "" {
			inBody = true
			continue
		}

		if inBody {
			data += line + "\n"
		} else {
			headerLines = append(headerLines, line)
			lower := strings.ToLower(line)
			if strings.HasPrefix(lower, "host:") {
				host = strings.TrimSpace(line[5:])
			} else if strings.HasPrefix(lower, "cookie:") {
				cookies = strings.TrimSpace(line[7:])
			}
		}
	}

	// 构建目标 URL
	if len(parts) >= 2 {
		path := parts[1]
		if host != "" {
			scheme := "http"
			if strings.Contains(raw, ":443") || strings.Contains(strings.ToLower(raw), "https") {
				scheme = "https"
			}
			target = fmt.Sprintf("%s://%s%s", scheme, host, path)
		}
	}

	data = strings.TrimSpace(data)
	headers = strings.Join(headerLines, "\n")

	return
}

// Worker SQLMap 工作协程
func (app *App) Worker(id int) {
	log.Printf("[Worker %d] 启动", id)

	for taskID := range app.taskChan {
		app.processTask(taskID)
	}
}

// processTask 处理单个任务
func (app *App) processTask(taskID string) {
	task, err := app.GetTask(taskID)
	if err != nil {
		log.Printf("获取任务失败: %v", err)
		return
	}

	log.Printf("[Task %s] 开始扫描: %s", task.ID[:8], task.Target)

	// 更新状态为运行中
	now := time.Now()
	task.Status = "running"
	task.StartedAt = &now
	app.UpdateTask(task)
	app.broadcast(map[string]interface{}{"type": "status", "task": task})

	// 准备请求文件
	reqFile := filepath.Join(app.workDir, task.ID+".req")
	if task.Request != "" {
		os.WriteFile(reqFile, []byte(task.Request), 0644)
	}

	// 构建 SQLMap 命令
	args := []string{
		"--batch",
		"--flush-session",
		"--is-dba",
		"--output-dir=" + app.workDir,
	}

	if task.Request != "" {
		args = append(args, "-r", reqFile)
	} else {
		args = append(args, "-u", task.Target)
		if task.Method == "POST" && task.Data != "" {
			args = append(args, "--data", task.Data)
		}
	}

	if task.Cookies != "" {
		args = append(args, "--cookie", task.Cookies)
	}

	// 解析额外参数
	if task.Options != "" {
		extraArgs := strings.Fields(task.Options)
		args = append(args, extraArgs...)
	}

	// 创建日志目录
	logsDir := filepath.Join(app.workDir, "logs")
	os.MkdirAll(logsDir, 0755)

	// 日志文件路径：logs/2024-01-16/task-id.log
	dateDir := filepath.Join(logsDir, time.Now().Format("2006-01-02"))
	os.MkdirAll(dateDir, 0755)
	logFile := filepath.Join(dateDir, task.ID+".log")
	task.LogFile = logFile

	// 执行 SQLMap
	cmd := exec.Command(app.sqlmapPath, args...)
	cmd.Dir = app.workDir

	// 获取输出
	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	if err := cmd.Start(); err != nil {
		task.Status = "failed"
		task.Result = "启动 SQLMap 失败: " + err.Error()
		finished := time.Now()
		task.FinishedAt = &finished
		app.UpdateTask(task)
		app.broadcast(map[string]interface{}{"type": "status", "task": task})
		return
	}

	// 打开日志文件
	logFileHandle, _ := os.Create(logFile)
	defer logFileHandle.Close()

	// 读取输出并写入文件
	var output strings.Builder
	go func() {
		reader := bufio.NewReader(stdout)
		for {
			line, err := reader.ReadString('\n')
			if err != nil {
				break
			}
			output.WriteString(line)
			logFileHandle.WriteString(line) // 写入日志文件

			// 实时广播输出
			app.broadcast(map[string]interface{}{
				"type":    "output",
				"task_id": task.ID,
				"line":    line,
			})
		}
	}()

	// 读取错误输出
	go func() {
		buf := make([]byte, 1024)
		for {
			n, err := stderr.Read(buf)
			if err != nil {
				break
			}
			output.Write(buf[:n])
			logFileHandle.Write(buf[:n]) // 写入日志文件
		}
	}()

	// 等待完成
	cmd.Wait()

	// 清理请求文件
	os.Remove(reqFile)

	// 分析结果（从内存中的输出分析，不再存数据库）
	outputStr := output.String()
	finished := time.Now()
	task.FinishedAt = &finished

	// 检测是否发现漏洞
	if strings.Contains(outputStr, "is vulnerable") ||
		strings.Contains(outputStr, "sqlmap identified the following injection") ||
		strings.Contains(outputStr, "Parameter:") && strings.Contains(outputStr, "Type:") {
		task.Status = "success"
		task.Vulnerable = true
		task.Result = "发现 SQL 注入漏洞!"

		// 提取数据库类型
		if idx := strings.Index(outputStr, "back-end DBMS:"); idx != -1 {
			end := strings.Index(outputStr[idx:], "\n")
			if end != -1 {
				task.DBMS = strings.TrimSpace(outputStr[idx+14 : idx+end])
			}
		}

		// 检测是否为 DBA
		if strings.Contains(outputStr, "current user is DBA: True") {
			val := true
			task.IsDBA = &val
		} else if strings.Contains(outputStr, "current user is DBA: False") {
			val := false
			task.IsDBA = &val
		}
	} else if strings.Contains(outputStr, "all tested parameters do not appear to be injectable") {
		task.Status = "failed"
		task.Vulnerable = false
		task.Result = "未发现 SQL 注入漏洞"
	} else {
		task.Status = "failed"
		task.Result = "扫描完成，无明确结果"
	}

	app.UpdateTask(task)
	app.broadcast(map[string]interface{}{"type": "status", "task": task})

	log.Printf("[Task %s] 完成: %s", task.ID[:8], task.Status)
}

// broadcast 广播消息到所有 WebSocket 客户端
func (app *App) broadcast(msg interface{}) {
	data, _ := json.Marshal(msg)

	app.wsLock.RLock()
	defer app.wsLock.RUnlock()

	for client := range app.wsClients {
		client.WriteMessage(websocket.TextMessage, data)
	}
}

// HTTP Handlers

func (app *App) handleIndex(w http.ResponseWriter, r *http.Request) {
	tmpl := template.Must(template.New("index").Parse(indexHTML))
	tmpl.Execute(w, nil)
}

func (app *App) handleAPI(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	path := strings.TrimPrefix(r.URL.Path, "/api")

	switch {
	case path == "/tasks" && r.Method == "GET":
		tasks, total, _ := app.GetTasks(50, 0)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"tasks": tasks,
			"total": total,
		})

	case path == "/tasks" && r.Method == "POST":
		var task Task
		if err := json.NewDecoder(r.Body).Decode(&task); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}

		// 如果提供了原始请求包，解析它
		if task.Request != "" {
			task.Target, task.Method, task.Data, task.Cookies, task.Headers = ParseRequest(task.Request)
		}

		if task.Name == "" {
			task.Name = "Task-" + time.Now().Format("0102-150405")
		}

		if err := app.CreateTask(&task); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}

		json.NewEncoder(w).Encode(task)

	case strings.HasPrefix(path, "/tasks/") && r.Method == "GET":
		id := strings.TrimPrefix(path, "/tasks/")
		task, err := app.GetTask(id)
		if err != nil {
			http.Error(w, "Task not found", 404)
			return
		}
		json.NewEncoder(w).Encode(task)

	case strings.HasPrefix(path, "/tasks/") && r.Method == "DELETE":
		id := strings.TrimPrefix(path, "/tasks/")
		app.DeleteTask(id)
		json.NewEncoder(w).Encode(map[string]bool{"ok": true})

	case path == "/stats":
		var pending, running, success, failed int
		app.db.QueryRow("SELECT COUNT(*) FROM tasks WHERE status='pending'").Scan(&pending)
		app.db.QueryRow("SELECT COUNT(*) FROM tasks WHERE status='running'").Scan(&running)
		app.db.QueryRow("SELECT COUNT(*) FROM tasks WHERE status='success'").Scan(&success)
		app.db.QueryRow("SELECT COUNT(*) FROM tasks WHERE status='failed'").Scan(&failed)

		json.NewEncoder(w).Encode(map[string]int{
			"pending": pending,
			"running": running,
			"success": success,
			"failed":  failed,
			"total":   pending + running + success + failed,
		})

	case path == "/cleanup" && r.Method == "POST":
		// 清理指定天数之前的日志，默认 7 天
		days := 7
		if d := r.URL.Query().Get("days"); d != "" {
			fmt.Sscanf(d, "%d", &days)
		}
		count, err := app.CleanupOldLogs(days)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		json.NewEncoder(w).Encode(map[string]interface{}{
			"ok":      true,
			"deleted": count,
			"days":    days,
		})

	default:
		http.Error(w, "Not found", 404)
	}
}

func (app *App) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := app.upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	app.wsLock.Lock()
	app.wsClients[conn] = true
	app.wsLock.Unlock()

	defer func() {
		app.wsLock.Lock()
		delete(app.wsClients, conn)
		app.wsLock.Unlock()
	}()

	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			break
		}
	}
}

func (app *App) Start(addr string) error {
	// 启动 workers
	for i := 0; i < app.maxWorkers; i++ {
		go app.Worker(i + 1)
	}

	// 恢复未完成的任务
	rows, _ := app.db.Query("SELECT id FROM tasks WHERE status='pending'")
	if rows != nil {
		for rows.Next() {
			var id string
			rows.Scan(&id)
			app.taskChan <- id
		}
		rows.Close()
	}

	// 设置路由
	http.HandleFunc("/", app.handleIndex)
	http.HandleFunc("/api/", app.handleAPI)
	http.HandleFunc("/ws", app.handleWebSocket)

	log.Printf("服务器启动: http://%s", addr)
	return http.ListenAndServe(addr, nil)
}

func main() {
	addr := flag.String("addr", ":8080", "监听地址")
	sqlmapPath := flag.String("sqlmap", "sqlmap", "SQLMap 路径")
	workers := flag.Int("workers", 2, "并发工作数（最大同时执行数）")
	dbPath := flag.String("db", "sqlmap-web.db", "数据库路径")
	workDir := flag.String("workdir", "./output", "工作目录")
	flag.Parse()

	app, err := NewApp(*dbPath, *sqlmapPath, *workDir, *workers)
	if err != nil {
		log.Fatal(err)
	}

	log.Fatal(app.Start(*addr))
}

// HTML 模板
const indexHTML = `<!DOCTYPE html>
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
        }
        header h1 { color: #00d4ff; font-size: 24px; }

        .stats {
            display: flex;
            gap: 20px;
        }
        .stat-item {
            text-align: center;
            padding: 10px 20px;
            background: rgba(255,255,255,0.05);
            border-radius: 8px;
        }
        .stat-value {
            font-size: 24px;
            font-weight: bold;
        }
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
        .form-group textarea { min-height: 200px; resize: vertical; }
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

        .task-list { max-height: 600px; overflow-y: auto; }
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

        .task-target {
            font-size: 12px;
            color: #888;
            word-break: break-all;
        }
        .task-time {
            font-size: 11px;
            color: #666;
            margin-top: 5px;
        }
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

        .tabs {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
        }
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

        .empty-state {
            text-align: center;
            padding: 40px;
            color: #666;
        }

        @media (max-width: 900px) {
            .main-grid { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🔍 SQLMap 自动化扫描平台</h1>
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
                <div class="panel" id="submit-panel">
                    <h2>📤 提交扫描任务</h2>
                    <form id="task-form">
                        <div class="form-group">
                            <label>任务名称 (可选)</label>
                            <input type="text" name="name" placeholder="留空自动生成">
                        </div>
                        <div class="form-group">
                            <label>HTTP 请求包 (推荐)</label>
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
                        <p>1. 在左侧粘贴 HTTP 请求包</p>
                        <p>2. 点击"开始扫描"提交任务</p>
                        <p>3. SQLMap 将自动检测 SQL 注入漏洞</p>
                        <p>4. 点击任务列表查看详细结果</p>
                        <br>
                        <p style="color: #ff9800;">⚠️ 仅用于授权的安全测试</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let currentTaskId = null;
        let ws = null;

        // WebSocket 连接
        function connectWS() {
            const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
            ws = new WebSocket(protocol + '//' + location.host + '/ws');

            ws.onmessage = (e) => {
                const msg = JSON.parse(e.data);
                if (msg.type === 'status') {
                    updateTaskInList(msg.task);
                    if (currentTaskId === msg.task.id) {
                        showTaskDetail(msg.task);
                    }
                    loadStats();
                } else if (msg.type === 'output' && msg.task_id === currentTaskId) {
                    const output = document.getElementById('detail-output');
                    output.textContent += msg.line;
                    output.scrollTop = output.scrollHeight;
                }
            };

            ws.onclose = () => setTimeout(connectWS, 3000);
        }

        // 加载统计
        async function loadStats() {
            const res = await fetch('/api/stats');
            const stats = await res.json();
            document.getElementById('stat-pending').textContent = stats.pending;
            document.getElementById('stat-running').textContent = stats.running;
            document.getElementById('stat-success').textContent = stats.success;
            document.getElementById('stat-failed').textContent = stats.failed;
        }

        // 当前筛选状态
        let currentFilter = 'all';
        let allTasks = [];

        // 加载任务列表
        async function loadTasks() {
            const res = await fetch('/api/tasks');
            const data = await res.json();
            allTasks = data.tasks || [];
            renderTasks();
        }

        // 渲染任务列表（带筛选）
        function renderTasks() {
            const list = document.getElementById('task-list');
            let tasks = allTasks;

            if (currentFilter !== 'all') {
                tasks = allTasks.filter(t => t.status === currentFilter);
            }

            if (tasks.length === 0) {
                const msg = currentFilter === 'all' ? '暂无任务' : '没有符合条件的任务';
                list.innerHTML = '<div class="empty-state">' + msg + '</div>';
                return;
            }

            list.innerHTML = tasks.map(task => createTaskItem(task)).join('');
        }

        // 创建任务项 HTML
        function createTaskItem(task) {
            const statusText = {
                'pending': '等待中',
                'running': '运行中',
                'success': '有漏洞',
                'failed': '安全'
            };

            let badges = '';
            if (task.dbms) badges += ` + "`" + `<span class="task-dbms">${task.dbms}</span>` + "`" + `;
            if (task.is_dba === true) badges += ` + "`" + `<span class="task-dba">DBA</span>` + "`" + `;

            return ` + "`" + `
                <div class="task-item ${task.status}" onclick="selectTask('${task.id}')">
                    <div class="task-header">
                        <span class="task-name">${task.name || 'Unnamed'}</span>
                        <span class="task-status ${task.status}">${statusText[task.status] || task.status}</span>
                    </div>
                    <div class="task-target">${task.target || 'N/A'}</div>
                    ${badges}
                    <div class="task-time">${new Date(task.created_at).toLocaleString()}</div>
                </div>
            ` + "`" + `;
        }

        // 更新列表中的任务
        function updateTaskInList(task) {
            // 更新 allTasks 数组
            const idx = allTasks.findIndex(t => t.id === task.id);
            if (idx >= 0) {
                allTasks[idx] = task;
            } else {
                allTasks.unshift(task);
            }

            // 重新渲染（保持筛选状态）
            renderTasks();
        }

        // 选择任务
        async function selectTask(id) {
            currentTaskId = id;
            const res = await fetch('/api/tasks/' + id);
            const task = await res.json();
            showTaskDetail(task);

            document.getElementById('welcome-panel').style.display = 'none';
            document.getElementById('detail-panel').classList.add('active');
        }

        // 显示任务详情
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

        // 删除任务
        async function deleteTask() {
            if (!currentTaskId || !confirm('确定删除此任务?')) return;

            await fetch('/api/tasks/' + currentTaskId, { method: 'DELETE' });
            currentTaskId = null;
            document.getElementById('detail-panel').classList.remove('active');
            document.getElementById('welcome-panel').style.display = 'block';
            loadTasks();
            loadStats();
        }

        // 提交表单
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

        // Tab 切换
        document.querySelectorAll('.tab').forEach(tab => {
            tab.onclick = () => {
                document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
                document.querySelectorAll('.tab-content').forEach(c => c.style.display = 'none');
                tab.classList.add('active');
                document.getElementById('tab-' + tab.dataset.tab).style.display = 'block';
            };
        });

        // 筛选按钮
        document.querySelectorAll('.filter-btn').forEach(btn => {
            btn.onclick = () => {
                document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                currentFilter = btn.dataset.filter;
                renderTasks();
            };
        });

        // 初始化
        connectWS();
        loadStats();
        loadTasks();
        setInterval(loadStats, 10000);
    </script>
</body>
</html>
`
