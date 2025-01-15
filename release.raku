#!/usr/bin/env raku

use JSON::Fast;

my constant @distros = 'Cro::Core',
                       'Cro::HTTP',
                       'Cro::TLS',
                       'Cro::WebApp',
                       'Cro::WebSocket',
                       'cro';
my constant %distro-dirs = 'Cro::Core' => 'cro-core',
                           'Cro::TLS' => 'cro-tls',
                           'Cro::HTTP' => 'cro-http',
                           'Cro::WebSocket' => 'cro-websocket',
                           'Cro::WebApp' => 'cro-webapp',
                           'cro' => 'cro';

multi MAIN(:$clean!) {
    shell "rm -rf $_" if .IO.d for %distro-dirs.values;
}

multi MAIN(:$reset!) {
    shell "cd $_ && git reset --hard HEAD" if .IO.d for %distro-dirs.values;
}

multi MAIN(:$get!) {
    shell "git clone git@github.com:/croservices/$_.git" unless .IO.d for %distro-dirs.values;
}

multi MAIN(:$prepare!) {
    # Change versioning scheme.
    # Generate release log template from Changes files and committers.

    my %versions = from-json $*PROGRAM.parent.add("versions.json").slurp;

    for %distro-dirs.values {
        unless .IO.d {
            conk "Missing directory '$_' (script expects Cro repos checked out in CWD)";
        }
    }

    for %distro-dirs.values {
        check-clean-diff($_);
        pull($_);
    }

    # Bump version number of docker image to use in templates.
    bump-oci-image-version(%versions<oci_image>);

    # Bump versions and commit bumps.
    my @bumped-distros;
    for @distros -> $name {
        my $dir = %distro-dirs{$name};
        my $bumped = bump-version($dir, $name, %versions<distros>, %versions<api>);
        @bumped-distros.push($name) if $bumped;
    }

    # Tag
    say "Pre-release checks passed; tagging releases";
    for @bumped-distros {
        my $dir = %distro-dirs{$_};
        my $version = %versions<distros>{$_};
        tag($dir, "release-$version");
        say "* $_";
    }

    say "Creating an announcement template";
    prepare-announcement(@bumped-distros, %versions);

    # Release
    say "Uploading to zef ecosystem";
    for @bumped-distros {
        my $dir = %distro-dirs{$_};
        say "# $_";
        do {
            shell "cd $dir && fez review";
        } while prompt("Does this look sane? [yn]") ne "y";
        shell "cd $dir && fez upload";
    }
}

sub prepare-announcement(@bumped-distros, %versions) {
    my $template = Q:to/EOT/;
        ## {{DATE}}

        The latest versions of the Cro libraries are:

        {{VERSIONS}}

        To use the Cro libraries in a project, it usually suffices to only depend on
        `Cro::HTTP` and optionally `Cro::WebApp` or `Cro::WebSocket`.

        {{DISTROS}}
        EOT

    my $distro-template = Q:to/EOT/;
        ### {{NAME}} {{VERSION}}

        {{CHANGES}}

        This release was contributed to by:
        {{CONTRIBUTORS}}
        EOT

    my $file = 'cro-website/docs/releases.md';

    my %changes;
    my $distros-text = @bumped-distros.map(-> $distro {
        my $dir = %distro-dirs{$distro};
        my $version = %versions<distros>{$distro};
        my $changes-file = "$dir/Changes".IO.slurp;
        do if $changes-file ~~ / ^^ $version [\h <-[ \n ]>*]? \n ( [ <!before \n \S > . ]+ ) / {
            my $changes = $0.trim-trailing.lines.map(*.substr(4)).join("\n");
            $distro-template
                .subst('{{NAME}}', $distro)
                .subst('{{VERSION}}', $version)
                .subst('{{CHANGES}}', $changes)
                .subst('{{CONTRIBUTORS}}', get-committers($dir).sort.join(", "))
        }
        else {
            conk "Missing Changes in $distro";
        }
    }).join("\n\n");

    my $versions-text = @distros.map({
        $_
        ~ ':ver<' ~ %versions<distros>{$_} ~ '>'
        ~ ':api<' ~ %versions<api> ~ '>' ~
        ~ ':auth<zef:cro>'
    }).join("\n");

    my $text = $template
               .subst('{{DATE}}', Date.today.Str)
               .subst('{{VERSIONS}}', $versions-text)
               .subst('{{DISTROS}}', $distros-text);

    my $releases = slurp($file);

    if $releases ~~ / "# Cro Release History" \n \n / {
        $releases ~~ s/ "# Cro Release History" \n \n /$/$text\n/;
    }
    else {
        note "Could not find \"# Cro Release History\" in $file, just spurting the announcement at the top.";
        $releases ~~ s/ ^ /$text\n/;
    }
    spurt $file, $releases;
}

sub bump-oci-image-version($version) {
    my $file = 'cro/lib/Cro/Tools/Template/Common.rakumod';
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
            shell "cd cro && git commit -m 'Bump docker images to $version' lib/Cro/Tools/Template/Common.rakumod && git push origin main";
        }
        else {
            die "Could not find version to update in $file";
        }
    }
}

sub bump-version($distro-dir, $name, %distro-versions, $api-version) {
    my $file = "$distro-dir/META6.json";
    my $json = slurp $file;
    my $meta = from-json $json;
    my $my-version = %distro-versions{$name};
    given $meta {
        my $updated;
        # Update the module version itself
        if $meta<version> eq $my-version {
            note "$distro-dir/META6.json already up to date with version number";
            return False;
        } else {
            $updated = $json.subst(/'"version"' \s* ':' \s* '"' <( <-["]>+ )> '"'/, $my-version);
        }

        # Update API version.
        if $meta<api> ne $api-version {
            $updated = $json.subst(/'"api"' \s* ':' \s* '"' <( <-["]>+ )> '"'/, $api-version);
        }

        # Next update dependencies
        for @($meta<depends>) -> $module {
            if $module ~~ /('Cro::' \w+)/ {
                $updated .= subst(/ '"depends"' \s* ':' \s* '[' <-[\]]>*? <( $module )> <-[\]]>*? ']' /, "$0:ver<{ %distro-versions{$0} }+>:api<$api-version>:auth<zef:cro>");
            }
        }

        # Update version in Changes
        my $changes-file = "$distro-dir/Changes";
        my $changes = $changes-file.IO.slurp;
        $changes ~~ s/'{{NEXT}}'/$my-version/;
        spurt $changes-file, $changes;

        if $updated ~~ /$my-version/ {
            spurt $file, $updated;
            shell "cd $distro-dir && git commit -m 'Bump version to $my-version' META6.json && git push origin main"
        }
        else {
            conk "Could not find version in $distro-dir/META6.json";
        }

        return True;
    }
    return False;
}

sub check-clean-diff($distro-dir) {
    if qqx/cd $distro-dir && git diff/ {
        conk "Dirty working tree in $distro-dir";
    }
}

sub pull($distro-dir) {
    shell "cd $distro-dir && git pull"
}

sub tag($distro-dir, $tag) {
    shell "cd $distro-dir && git tag -a -m '$tag' $tag && git push --tags origin";
}

sub get-latest-release-tag($distro-dir) {
    my $proc = shell "cd $distro-dir && git tag --list 'release-*' --sort=-v:refname", :out;
    my $out = $proc.out.slurp: :close;
    $out.lines[0];
}

sub get-committers($distro-dir) {
    my $last-tag = get-latest-release-tag $distro-dir;
    my $proc = shell "cd $distro-dir && git log --no-merges --pretty=format:\"\%cn\" $last-tag..HEAD", :out;
    my $out = $proc.out.slurp: :close;
    $out.lines.unique;
}

sub conk($err) {
    note $err;
    exit 1;
}
