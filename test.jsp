<%@ page language="java" contentType="application/json; charset=UTF-8" %>
<%
response.setHeader("Access-Control-Allow-Origin", "*");
out.print("{\"success\":true,\"message\":\"JSP works!\"}");
%>
