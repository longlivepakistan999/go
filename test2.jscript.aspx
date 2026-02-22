<%@ Page Language="JScript" Debug="true" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Collections" %>
<%
Response.ContentType = "application/json";
try {
    var path = Server.MapPath("/");
    var dir = new DirectoryInfo(path);
    Response.Write("{\"exists\":" + dir.Exists + ",\"path\":\"" + path.replace(/\\/g, "\\\\") + "\"}");
} catch (e) {
    Response.Write("{\"error\":\"" + e.message.replace(/"/g, "'") + "\"}");
}
%>
