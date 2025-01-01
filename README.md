How to do a release
===================

- Change the version numbers in `versions.json` to the versions you want to
  release. Keep the versions of modules you don't want to release unchanged.
- Run `release.raku --prepare` in a folder containing clones of all of the
  Cro distros:
  - cro-core
  - cro-tls
  - cro-http
  - cro-websocket
  - cro-webapp
  - cro
  This will then automatically do the following:
  - `git pull` in all the repos
  - Create a commit and push in `cro` that bumps the OCI image version.
  - For each distro that has a changed version number in `versions.json`:
    - Update the `version` and `api` in `META6.json`.
    - Update all the `depends` versions of the other Cro distros in
      `META6.json`.
    - Update the version in the `Changes` file.
    - Create a commit and push.
  - Create and push a release tag in all updated distros.
  - Add a skeleton release announcement section to
    `cro-website/docs/releases.md`.
- Complete the pre-generated release notes in `cro-website/docs/releases.md`.
- Commit, push and publish the release announcement.
- Commit and push the changes to the `versions.json` file.

