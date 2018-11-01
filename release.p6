my constant @distros = 'cro-core', 'cro-tls', 'cro-http', 'cro-websocket', 'cro-zeromq', 'cro', 'cro-http-test', 'cro-http-session-redis';

sub MAIN(Str $version where /^\d+'.'\d+['.'\d+]?$/) {
    for @distros {
        unless .IO.d {
            conk "Missing directory '$_' (script expects Cro repos checked out in CWD)";
        }
    }

    for @distros {
        check-clean-diff($_);
    }

    # Bump version number of docker image to use in templates.
    bump-docker-image-version($version);

    # Bump versions and commit bumps.
    for @distros {
        bump-version($_, $version);
    }
    say "Pre-release checks passed; writing tarballs";
    for @distros {
        my $dist-name = "$_-$version";
        my $tar-name = "$dist-name.tar.gz";
        write-tar($_, $dist-name, $tar-name);
        say "* $tar-name";
    }

    say "Tagging releases";
    for @distros {
        tag($_, "release-$version");
        say "* $_";
    }
}

sub bump-docker-image-version($version) {
    my $file = 'cro/lib/Cro/Tools/Template/Common.pm6';
    given slurp($file) -> $common {
        if $common ~~ /"my constant CRO_DOCKER_VERSION = '$version'"/ {
            note "Docker version already updated";
            return;
        }
        my $updated = $common.subst:
            /"my constant CRO_DOCKER_VERSION = '" <( <-[']>+/,
            $version;
        if $updated ~~ /$version/ {
            spurt $file, $updated;
            shell "cd cro && git commit -m 'Bump docker images to $version' lib/Cro/Tools/Template/Common.pm6 && git push origin master"
        }
        else {
            die "Could not find version to update in $file";
        }
    }
}

sub bump-version($distro, $version) {
    my $file = "$distro/META6.json";
    given slurp($file) -> $json {
        if $json ~~ /$version/ {
            note "$distro/META6.json already up to date with version number";
            return;
        }
        my $updated = $json.subst(/'"version"' \s* ':' \s* '"' <( <-["]>+ )> '"'/, $version);
        if $updated ~~ /$version/ {
            spurt $file, $updated;
            shell "cd $distro && git commit -m 'Bump version to $version' META6.json && git push origin master"
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

sub tag($distro, $tag) {
    shell "cd $distro && git tag -a -m '$tag' $tag && git push --tags origin"
}

sub conk($err) {
    note $err;
    exit 1;
}
