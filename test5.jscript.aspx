<%@ Page Language="JScript" Debug="true" %>
<%@ Import Namespace="System.IO" %>
<%
Response.ContentType = "application/json";

function escStr(s) {
    if (s == null) return "";
    return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t");
}

// Use plain JS object with array of key-value pairs for serialization
function JsonObject() {
    this._keys = [];
    this._vals = [];
}
JsonObject.prototype.set = function(k, v) {
    this._keys.push(k);
    this._vals.push(v);
};
JsonObject.prototype.toJson = function() {
    var parts = "";
    for (var i = 0; i < this._keys.length; i++) {
        if (i > 0) parts += ",";
        parts += '"' + escStr(this._keys[i]) + '":' + toJson(this._vals[i]);
    }
    return "{" + parts + "}";
};

function JsonArray() {
    this._items = [];
}
JsonArray.prototype.add = function(v) {
    this._items.push(v);
};
JsonArray.prototype.toJson = function() {
    var parts = "";
    for (var i = 0; i < this._items.length; i++) {
        if (i > 0) parts += ",";
        parts += toJson(this._items[i]);
    }
    return "[" + parts + "]";
};

function toJson(obj) {
    if (obj == null) return "null";
    if (typeof obj == "boolean") return obj ? "true" : "false";
    if (typeof obj == "number") return obj.toString();
    if (typeof obj == "string") return '"' + escStr(obj) + '"';
    if (obj instanceof JsonObject) return obj.toJson();
    if (obj instanceof JsonArray) return obj.toJson();
    return '"' + escStr(String(obj)) + '"';
}

try {
    var data = new JsonObject();
    data.set("name", "test");
    data.set("count", 123);
    data.set("flag", true);

    var items = new JsonArray();
    var item1 = new JsonObject();
    item1.set("id", 1);
    item1.set("value", "hello");
    items.add(item1);

    data.set("items", items);

    Response.Write(toJson(data));
} catch (e) {
    Response.Write("{\"error\":\"" + String(e.message).replace(/"/g, "'") + "\"}");
}
%>
