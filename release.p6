my constant @distros = 'cro-core', 'cro-tls', 'cro-http', 'cro-websocket', 'cro-zeromq', 'cro';

sub MAIN(Str $version where /^\d+'.'\d+['.'\d+]?$/) {
    for @distros {
        unless .IO.d {
            conk "Missing directory '$_' (script expects Cro repos checked out in CWD)";
        }
    }

    for @distros {
        check-version($_, $version);
        check-clean-diff($_);
    }

    say "Pre-release checks passed; writing tarballs";
    for @distros {
        my $dist-name = "$_-$version";
        my $tar-name = "$dist-name.tar.gz";
        write-tar($_, $dist-name, $tar-name);
        say "* $tar-name";
    }
}

sub check-version($distro, $target-version) {
    given slurp("$distro/META6.json") -> $json {
        with $json ~~ /'"version"' \s* ':' \s* '"' (<-["]>+) '"'/ {
            if .[0] ne $target-version {
                conk "Version in $distro/META6.json is {.[0]}, not $target-version";
            }
        }
        else {
            conk "Could not find version in $distro/META6.json";
        }
    }
}

sub check-clean-diff($distro) {
    if qqx/cd $distro && git diff/ {
        conk "Dirty working tree in $distro";
    }
}

sub write-tar($distro, $dist-name, $tar-name) {
    shell "cd $distro && git archive --prefix=$dist-name/ -o ../$tar-name HEAD"
}

sub conk($err) {
    note $err;
    exit 1;
}
