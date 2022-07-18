use JSON::Fast;

my constant @distros = 'cro-core', 'cro-tls', 'cro-http', 'cro-websocket',
                       'cro-webapp', 'cro';

multi MAIN(:$clean!) {
    shell "rm -rf $_" if .IO.d for @distros;
}

multi MAIN(:$get!) {
    shell "git clone https://github.com/croservices/$_.git" unless .IO.d for @distros;
}

multi MAIN(Str $version where /^\d+'.'\d+['.'\d+]?$/) {
    for @distros {
        unless .IO.d {
            conk "Missing directory '$_' (script expects Cro repos checked out in CWD)";
        }
    }

    for @distros {
        check-clean-diff($_);
        pull($_);
    }

    # Bump version number of docker image to use in templates.
    bump-docker-image-version($version);

    # Bump versions and commit bumps.
    for @distros {
        bump-version($_, $version);
    }

    # Tag
    say "Pre-release checks passed; tagging releases";
    for @distros {
        tag($_, "release-$version");
        say "* $_";
    }

    # Release
    say "Uploading to zef ecosystem";
    for @distros {
        say "# $_";
        shell "cd $_ && fez upload";
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
    my $json = slurp $file;
    my $meta = from-json $json;
    given $meta {
        my $updated;
        # Update the module version itself
        if $meta<version> eq $version {
            note "$distro/META6.json already up to date with version number";
        } else {
            $updated = $json.subst(/'"version"' \s* ':' \s* '"' <( <-["]>+ )> '"'/, $version);
        }
        # Next update dependencies
        for @($meta<depends>) -> $module {
            if $module ~~ /('Cro::' \w+)/ {
                $updated .= subst(/ '"depends"' \s* ':' \s* '[' <-[\]]>*? <( $module )> <-[\]]>*? ']' /, "$0\:ver<$version>");
            }
        }

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

sub pull($distro) {
    shell "cd $distro && git pull"
}

sub tag($distro, $tag) {
    shell "cd $distro && git tag -a -m '$tag' $tag && git push --tags origin"
}

sub conk($err) {
    note $err;
    exit 1;
}
