<%@ Page Language="JScript" Debug="true" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Collections" %>
<%
Response.ContentType = "application/json";

function escStr(s) {
    if (s == null) return "";
    return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t");
}

function toJson(obj) {
    if (obj == null) return "null";
    var t = obj.GetType().Name;
    if (t == "Boolean") return obj ? "true" : "false";
    if (t == "Int32" || t == "Int64" || t == "Double" || t == "Single" || t == "Decimal") return obj.ToString();
    if (t == "String") return '"' + escStr(obj) + '"';
    if (t == "Hashtable") {
        var ht = obj;
        var parts = "";
        var first = true;
        // Use GetEnumerator on the hashtable itself, not on Keys
        var en = ht.GetEnumerator();
        while (en.MoveNext()) {
            if (!first) parts += ",";
            first = false;
            parts += '"' + escStr(en.Key) + '":' + toJson(en.Value);
        }
        return "{" + parts + "}";
    }
    if (t == "ArrayList") {
        var arr = obj;
        var items = "";
        for (var i = 0; i < arr.Count; i++) {
            if (i > 0) items += ",";
            items += toJson(arr[i]);
        }
        return "[" + items + "]";
    }
    return '"' + escStr(obj.ToString()) + '"';
}

try {
    var data = new Hashtable();
    data["name"] = "test";
    data["count"] = 123;
    data["flag"] = true;

    var items = new ArrayList();
    var item1 = new Hashtable();
    item1["id"] = 1;
    item1["value"] = "hello";
    items.Add(item1);

    data["items"] = items;

    Response.Write(toJson(data));
} catch (e) {
    Response.Write("{\"error\":\"" + e.message.replace(/"/g, "'") + "\"}");
}
%>
