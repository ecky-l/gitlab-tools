#!/bin/bash

errorExit() {
	echo "Error: $1"
	exit 1
}
set -o pipefail

WIP_PREFIX=""

# process args
while [[ $1 =~ ^- ]]
do
    arg=$1
    case $arg in
        -w|--wip)
            # work in progress flag for gitlab merge request
            WIP_PREFIX="WIP "
            shift
            ;;
        --)
            # dashed arguments after the -- belong to git
            # not yet necessary
            shift
            break
            ;;
    esac
done

ORIGIN=origin
if [[ -n ${1} ]]; then ORIGIN=${1}; fi 
CFG_FILE=.gitlab.${ORIGIN}.json

test -f "${CFG_FILE}" || errorExit "Config file ${CFG_FILE} does not exist!"
read -r GITLAB_URL PRIVATE_TOKEN PROJECT_ID <<< $(cat ${CFG_FILE} | jq -er '.gitlab_url, .private_token, .project_id') || \
                    errorExit "Config in ${CFG_FILE} must contain all of the variables gitlab_url private_token and project_id"
GITLAB_API_URL=${GITLAB_URL}/api/v4
PROJECT_ID=$(echo ${PROJECT_ID} | sed 's/\//%2F/g')

# Get info about last commit, description etc.
COMMIT=$(git log --pretty=%h | head -n1)
REMOVE_SOURCE_BRANCH=true
TITLE=$(git log --pretty=%s | head -n1)
DESCRIPTION=$(git log --pretty=%H | head -n1 | git show | tail -n +2)

# Construct source/target branch from the info.
# The source branch is an abbreviated form of the commit subject (first line of the commit message). It
# contains all characters from the subject but non-ascii characters are removed and spaces are substituted by dashes
# Remove non-ascii chars could be done by tr -cd '\11\12\15\40-\176', but is done automatically by git log --pretty=%f
SOURCE_BRANCH=$(git log --pretty=%f | head -n1 | cut -c1-80)
LOCAL_BRANCH=`git status -sb | head -n1 | cut -d' ' -f2 | sed 's/\.\.\./ /' | cut -d' ' -f1`
TARGET_BRANCH=$(git status -sb | head -n1 | cut -d' ' -f2 | cut -d'/' -f2)

echo $TARGET_BRANCH
if [[ ${LOCAL_BRANCH} =~ ^mr-${ORIGIN}-[0-9]+$ ]]; then
    MR_IID=`echo ${LOCAL_BRANCH} | cut -d'-' -f3`
    GITLAB_API_PROJECT_URL=${GITLAB_API_URL}/projects/${PROJECT_ID}
    read -r MR_SOURCE MR_TARGET MR_STATE <<< `curl -s ${GITLAB_API_PROJECT_URL}/merge_requests/${MR_IID} \
            -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" | \
        jq -er .source_branch,.target_branch,.state` || errorExit "Cannot fetch merge request ${MR_IID}"

    if [ $MR_STATE != "opened" ]; then
        echo "Merge Request ${MR_IID} is ${MR_STATE} and this branch is invalid. Checkout and pull ${MR_TARGET}!"
        exit 1
    fi

    if [ ${MR_SOURCE} == ${SOURCE_BRANCH} ]; then
        echo "This is an open merge request: !${MR_IID} with the same commit message ${COMMIT}. It will be refreshed!"
        git push -f ${ORIGIN} HEAD:${SOURCE_BRANCH} || errorExit "push was not successful"
        echo ""
        exit 0
    fi

    echo "This is an open merge request: !${MR_IID} with an apparently new commit."
    while true; do
        read -p "[A]dd new commit to !${MR_IID} (or update when the last one was ammended), create a [N]ew merge request or [C]ancel? " rnc
        case $rnc in
            [Aa]* )
                echo "pushing amended commit ${COMMIT} to existing review branch: ${MR_SOURCE} ..."
                git push -f ${ORIGIN} HEAD:${MR_SOURCE} || errorExit "push was not successful"
                echo ""
                exit 0
                ;;
            [Nn]* )
                TARGET_BRANCH=${MR_SOURCE}
                # fall through to creating a new merge request
                break
                ;;
            * )
                exit 0
                ;;
        esac
    done
fi


# Push the last commit to a new branch (which was constructed from the commits subject before
echo "pushing commit ${COMMIT} to new review branch: ${SOURCE_BRANCH} ..."
git push -f ${ORIGIN} HEAD:${SOURCE_BRANCH} || errorExit "push was not successful"
echo ""

# Get gitlab users from the API and select one. Then, the id of this user is acquired to be set in the mr input.
USERS=( $(curl -s ${GITLAB_API_URL}/users?per_page=100 -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" | jq -er '.[] | .username') ) || \
					errorExit "Cannot acquire list of users from gitlab at ${GITLAB_URL}"
PS3='To whom do you want to assign the review? '
select ASSIGNEE in "${USERS[@]}"; do break; done
ASSIGNEE_ID=$(curl -s ${GITLAB_API_URL}/users?username=${ASSIGNEE} -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" | jq -er '.[] | .id') || \
					errorExit "Cannot get assignee id for user ${ASSIGNEE} from gitlab at ${GITLAB_URL}"
echo "Assigning the merge request to ${ASSIGNEE} (who has user id ${ASSIGNEE_ID})"
echo ""

# Create the actual merge request via the gitlab API
JSON_PAYLOAD="{
	\"source_branch\": \"${SOURCE_BRANCH}\",
	\"target_branch\": \"${TARGET_BRANCH}\",
	\"remove_source_branch\": true,
	\"title\": \"${WIP_PREFIX} ${TITLE}\",
	\"assignee_id\": \"${ASSIGNEE_ID}\"
}"


GITLAB_API_PROJECT_URL=${GITLAB_API_URL}/projects/${PROJECT_ID}
OUT=$(curl -s ${GITLAB_API_PROJECT_URL}/merge_requests -X POST -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}" -H "Content-Type: application/json" --data "${JSON_PAYLOAD}") || errorExit "Cannot create Merge request! Sorry, you must do it manually :(."

ERROR_MSG=$(echo $OUT | jq -r '.message | .[]' 2>/dev/null)
if [ $? == 0 ]; then
	echo "${ERROR_MSG}"
    exit 0
fi

read MERGE_REQ_ID MERGE_REQ_WEB_URL <<< $(echo ${OUT} | jq -er '.iid, .web_url') || \
                    errorExit "id or web_url of merge request not found in output"
echo "Successfully created merge request !${MERGE_REQ_ID} and assigned to ${ASSIGNEE}."
echo "Point your browser here to see the result: ${MERGE_REQ_WEB_URL}"
echo ""

MR_BRANCH=mr-${ORIGIN}-${MERGE_REQ_ID} # _${TARGET_BRANCH}
FIRST_LOCAL_COMMIT=$(echo $(git merge-base HEAD origin/${TARGET_BRANCH}))
git branch ${MR_BRANCH} && git reset --keep ${FIRST_LOCAL_COMMIT}
git checkout ${MR_BRANCH}
git branch -u origin/${SOURCE_BRANCH}
echo "A local branch \"${MR_BRANCH}\" was created and checked out. If you want to amend the merge request, do: "
echo ""
echo "  * make your changes ..., then"
echo "  * \"git add [-u/...]\" to add the changes"
echo "  * \"git commit --amend\" to amend the commit (message prefilled, don't touch)"
echo "  * \"git push -f ${ORIGIN} HEAD:${SOURCE_BRANCH}\" to force-push to the merge request branch"
echo ""
echo "When the merge request is done and merged, you may delete the local branch ${MR_BRANCH}"
