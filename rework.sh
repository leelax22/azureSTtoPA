#!/bin/bash

# Load variables from .env file
export $(grep -v '^#' .env | xargs)

# Print the variables for debugging. Don't do this in a production environment as it exposes your secrets.
echo $GITHUB_USERNAME
echo $GITHUB_TOKEN
echo $REPO_NAME

# Specify the commits you want to modify
commits=("8d66af547fce5d7c7f6e3a220e6e4da085035060"
"ccc4a3fea2267c3174ea7ae3464e24cc817cba65"
"55db1a15d0d19413f24ff413d1fa4987c6d3b432"
"24cf6cf20e0fd4b787807c8f092746f45d8168fd"
"b0fcc0696a6156f0e2d0cc562e992803f68ef119"
"5d727ee880431502ace0a771e373ad0911346c6b")

# Checkout the branch of your repository
git clone https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}
cd ${REPO_NAME}

# Iterate through each commit
for commit in "${commits[@]}"
do
   # Rebase interactively up to the commit before the one to be changed
   git rebase -i $commit^

   # In the editor that comes up, replace `pick` with `edit` for the commit you want to change, then save and close
   # Since we're scripting this, we'll use sed to do that editing for us
   sed -i 's/pick/edit/' .git/rebase-merge/git-rebase-todo

   # Change the author of the commit
   git commit --amend --author="enzo-g <enzo@gautier.it>" --no-edit

   # Continue the rebase
   git rebase --continue
done

# Finally, push the amended commits to GitHub
# WARNING: this will overwrite the remote branch. Be sure of what you're doing.
git push origin main --force

# Clean up
unset GITHUB_USERNAME GITHUB_TOKEN REPO_NAME
