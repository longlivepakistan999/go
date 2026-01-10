using System;
using System.IO;
using System.Text;
using System.Web;

namespace IISHtmlInjectionModule
{
    /// <summary>
    /// IIS HTTP 模块 - 在 HTML 响应中注入自定义内容
    /// 仅用于您拥有和控制的网站
    /// </summary>
    public class HtmlInjectionModule : IHttpModule
    {
        // 要注入的 HTML 内容
        private const string InjectedHtml = "<div style=\"background-color:#ffeb3b;color:#000;padding:10px;text-align:center;font-size:14px;\"><b>此网址属于 XXX 拥有</b></div>";

        public void Init(HttpApplication context)
        {
            context.BeginRequest += OnBeginRequest;
        }

        private void OnBeginRequest(object sender, EventArgs e)
        {
            HttpApplication app = (HttpApplication)sender;
            HttpResponse response = app.Context.Response;

            // 使用自定义过滤器包装响应流
            response.Filter = new HtmlInjectionFilter(response.Filter, response.ContentEncoding);
        }

        public void Dispose()
        {
            // 清理资源
        }
    }

    /// <summary>
    /// 响应流过滤器 - 用于修改 HTML 内容
    /// </summary>
    public class HtmlInjectionFilter : Stream
    {
        private readonly Stream _responseStream;
        private readonly Encoding _encoding;
        private readonly MemoryStream _bufferStream;

        // 要注入的 HTML 内容
        private const string InjectedHtml = "<div style=\"background-color:#ffeb3b;color:#000;padding:10px;text-align:center;font-size:14px;\"><b>此网址属于 XXX 拥有</b></div>";

        public HtmlInjectionFilter(Stream responseStream, Encoding encoding)
        {
            _responseStream = responseStream;
            _encoding = encoding ?? Encoding.UTF8;
            _bufferStream = new MemoryStream();
        }

        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => _bufferStream.Length;

        public override long Position
        {
            get => _bufferStream.Position;
            set => _bufferStream.Position = value;
        }

        public override void Flush()
        {
            // 获取缓冲的内容
            string html = _encoding.GetString(_bufferStream.ToArray());

            // 检查是否为 HTML 内容
            if (IsHtmlContent(html))
            {
                // 在 <body> 标签后注入内容
                html = InjectContent(html);
            }

            // 写入修改后的内容
            byte[] buffer = _encoding.GetBytes(html);
            _responseStream.Write(buffer, 0, buffer.Length);
            _responseStream.Flush();
        }

        private bool IsHtmlContent(string content)
        {
            if (string.IsNullOrEmpty(content))
                return false;

            string trimmed = content.TrimStart().ToLowerInvariant();
            return trimmed.StartsWith("<!doctype html") ||
                   trimmed.StartsWith("<html") ||
                   trimmed.Contains("<body");
        }

        private string InjectContent(string html)
        {
            // 尝试在 <body> 标签后注入
            int bodyIndex = html.IndexOf("<body", StringComparison.OrdinalIgnoreCase);
            if (bodyIndex >= 0)
            {
                int closeTagIndex = html.IndexOf('>', bodyIndex);
                if (closeTagIndex >= 0)
                {
                    return html.Insert(closeTagIndex + 1, InjectedHtml);
                }
            }

            // 如果没有找到 <body>，尝试在 <html> 标签后注入
            int htmlIndex = html.IndexOf("<html", StringComparison.OrdinalIgnoreCase);
            if (htmlIndex >= 0)
            {
                int closeTagIndex = html.IndexOf('>', htmlIndex);
                if (closeTagIndex >= 0)
                {
                    return html.Insert(closeTagIndex + 1, InjectedHtml);
                }
            }

            // 如果都没有找到，在开头注入
            return InjectedHtml + html;
        }

        public override void Write(byte[] buffer, int offset, int count)
        {
            _bufferStream.Write(buffer, offset, count);
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            throw new NotSupportedException();
        }

        public override long Seek(long offset, SeekOrigin origin)
        {
            throw new NotSupportedException();
        }

        public override void SetLength(long value)
        {
            throw new NotSupportedException();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _bufferStream?.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
