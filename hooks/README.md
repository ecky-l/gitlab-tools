## Useful client githooks

This directory contains some git hooks, which tend to be useful. Currently it is one hook, which ensures that whenever you commit some change, a prefix (i.e. JIRA story ID) is extracted from the current branch and put into the commit message as the first word in [brackets]. This is useful as most people want to have a story/issue from their project management system linked in their commits, so that they can later refer from the git log.

### Usage

Once the hooks are installed (see below), just make sure that your working branch contains the preferred prefix, i.e. the JIRA issue ID, separated by a hyphen from a short description. For instance, if the story ID is *PROJECT-1234*, your branch name must be `PROJECT-1234-some-description`. Then, when commiting changes to the branch, the prefix to every commit message will always be `[PROJECT-1234] ` automatically, which can be extended by your usual commit message. When you do a commit via `git commit -m "blabla", the actual commit message will be `[PROJECT-1234] blabla`.

Its as easy as that, but may be very useful in daily work.

### installation

To install the hooks, you can follow one of the two options:

* copy them into the `.git/` directory inside your project
* copy them into your global core.hooksPath directory

The (preferred) latter option ensures that the hooks are used in every git repository you have cloned or will be cloning in the future. For that to work, create a directory and configure it globally as the `core.hooksPath`, i.e.

```
$ mkdir -p ~/.githooks
$ git config --global core.hooksPath ${HOME}/.githooks
```

Then copy the hooks into that directory.