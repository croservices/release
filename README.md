How to do a release
===================

- Have all of the 6 core Cro projects
  - cro-core
  - cro-tls
  - cro-http
  - cro-websocket
  - cro-webapp
  - cro
  as well as the website (cro-website) checked out in a folder.
- Ensure the `fez` program is available and you are logged in and are a member
  of the `cro` org.
- Ensure all the clones of each project have a remote called `origin` that
  allows writes.
- Change the version numbers in `versions.json` to the versions you want to
  release. Keep the versions of modules you don't want to release unchanged.
- Run `release.raku --prepare` in the parent folder of of the above mentioned
  repos.
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

