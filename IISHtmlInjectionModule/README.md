# IIS HTML 注入模块

一个简单的 IIS HTTP 模块，用于在 HTML 响应中注入自定义内容。

## 功能

- 自动检测 HTML 响应
- 在 `<body>` 标签后注入自定义 HTML 内容
- 支持自定义样式

## 编译

```bash
# 使用 .NET Framework 4.8
dotnet build -c Release
```

或者使用 Visual Studio 打开 `.csproj` 文件进行编译。

## 安装步骤

### 1. 编译模块

编译后会生成 `IISHtmlInjectionModule.dll` 文件。

### 2. 部署到网站

将 `IISHtmlInjectionModule.dll` 复制到网站的 `bin` 目录。

### 3. 配置 Web.config

在网站的 `Web.config` 文件中添加模块配置：

```xml
<configuration>
  <system.webServer>
    <modules>
      <add name="HtmlInjectionModule"
           type="IISHtmlInjectionModule.HtmlInjectionModule, IISHtmlInjectionModule"
           preCondition="managedHandler" />
    </modules>
  </system.webServer>
</configuration>
```

### 4. 全局安装（可选）

如果要在 IIS 服务器级别安装：

1. 将 DLL 安装到 GAC（全局程序集缓存）
2. 在 IIS 管理器中添加模块

## 自定义注入内容

修改 `HtmlInjectionModule.cs` 中的 `InjectedHtml` 常量：

```csharp
private const string InjectedHtml = "<div style=\"...\"><b>您的自定义内容</b></div>";
```

## 注意事项

⚠️ **重要提示：此模块仅应用于您拥有和控制的网站。**

- 仅在您拥有的服务器和网站上使用
- 不要用于修改他人网站的内容
- 建议在测试环境中先验证功能

## 许可证

MIT License
