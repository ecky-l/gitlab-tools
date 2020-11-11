# gitlab-tools
Scripts to automatically create/manage merge requests for gitlab

## Description

The shell scripts utilize the [https://docs.gitlab.com/ee/api/README.html](gitlab API) to create/manage merge request from one or more commits in the current branch and assign it to a user of choice.

## Requirements

For the shell scripts:

* bash
* curl
* [https://stedolan.github.io/jq/](jq)

## Setup

You need an API token from your gitlab server. This can be generated on the "Settings"->"Access Tokens" Page.

Once you have it, clone the project for which you want to create MRs and create a file inside its toplevel directory, which looks like this:

  {
    "gitlab_url": "<url of your gitlab server>",
    "private_token": "<your access token>",
    "project_id": "<group>/<project name>"
  }

The file must be named with .gitlab.[remote].json, where [remote] is the identifier of your remote, i.e. "origin" -> .gitlab.origin.json. Add the entry .gitlab.\*.json to your .gitignore so that you don't accidently check in the files.

You need such a file in every project for which you want to create merge requests with these scripts

Furthermore it is advisable to create aliases in your ~/.gitconfig to easily use the scripts. I have

  [alias]
      mrpush = !sh /path/to/this/repo/sh/create-mr.sh
      mrclean = !sh /path/to/this/repo/sh/cleanup-mr.sh

With this you can simply call "git mrpush" or "git mrclean" respectively. Further description assumes you have done so.


## Usage

With the setup above and the aliases, you can use

  git mrpush

to push the last local commits to a new branch on the gitlab server and create a merge request. The remote branch name will be the branch-friendly name of the last commit message.
A new local branch will be created with the name mr-[remote]-[mr ID] and set up to track the remote branch.

Example: The last commit message is "a simple change", the remote is "origin" and the ID of the created MR is 42. The local branch name is then "mr-origin-42" and it follows the remote branch origin/a-simple-change.
With "git status -sb" you will see:

  ## mr-origin-42...origin/a-simple-change

During the call to "git mrpush" you will see the url of the newly created merge request on your gitlab server and can choose a user to assign it to (including yourself). With "git mrpush -w" the merge request will be set to WIP. 
For further commits to the merge request, you can simply commit and push your changes on the branch.

When the MR is done and the remote branch was deleted, you can cleanup the local branch with

  git mrclean

The command will check for every local mr-[remote]-\* branch if there is an appropriate merge request open (by looking at the ID, the last identifier in the branch name) and if there isn't, it will call "git branch -D" on the local branch.
 
## Compatibility

The scripts are known to work on macOS >= 10.14.x with the default bash versions. Other bash versions, e.g. on linux, might or might not work. Fixes are welcome ;).

