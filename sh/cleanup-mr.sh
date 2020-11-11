#!/bin/sh

errorExit() {
	echo "Error: $1"
	exit 1
}
set -o pipefail

ORIGIN=origin
if [[ -n ${1} ]]; then ORIGIN=${1}; fi
CFG_FILE=.gitlab.${ORIGIN}.json
test -f "${CFG_FILE}" || errorExit "Config file ${CFG_FILE} does not exist!"
read -r GITLAB_URL PRIVATE_TOKEN PROJECT_ID <<< `cat ${CFG_FILE} | jq -er '.gitlab_url, .private_token, .project_id'` || \
                    errorExit "Config in ${CFG_FILE} must contain all of the variables gitlab_url private_token and project_id"
GITLAB_API_URL=${GITLAB_URL}/api/v4
PROJECT_ID=`echo ${PROJECT_ID} | sed 's/\//%2F/g'`

LOCAL_MR_BRANCHES=`git branch --column --list mr-${ORIGIN}-* | tr '*' ' '`
echo "Cleaning up orphaned merge requests, checking local branches\n${LOCAL_MR_BRANCHES}"
if [[ ${LOCAL_MR_BRANCHES} =~ ^$ ]]; then
    echo "Nothing to cleanup"
    exit 0
fi

echo ""
GITLAB_API_PROJECT_URL=${GITLAB_API_URL}/projects/${PROJECT_ID}
MR_OUT=`curl -s ${GITLAB_API_PROJECT_URL}/merge_requests?state=opened -H "PRIVATE-TOKEN: ${PRIVATE_TOKEN}"` || \
    errorExit "cannot retrieve merge requests"

# remove line endings and funny characters
MR_OUT=`echo $MR_OUT | tr -d '\15\32' | tr '\n' ' '`

MERGE_REQUESTS=`echo $MR_OUT | jq -er .[]`
if [ -n "${MERGE_REQUESTS}" ]; then
    MERGE_REQUESTS=`echo ${MR_OUT} | tr '\n' ' ' | jq -er '.[] | .iid'` || errorExit "Cannot retrieve merge requests"
fi

for lb in ${LOCAL_MR_BRANCHES}; do
    iid=`echo $lb | cut -d'-' -f3`
    found=false
    for rb in ${MERGE_REQUESTS}; do
        if [ $iid == $rb ]; then found=true; fi
    done

    if ! $found ; then
        descr=`git log $lb --pretty=%s | head -n1`
        while true; do
            read -p "Local branch $lb ($descr) appears to be an orphaned merge request. Delete? (y/N) " yn
            case $yn in
                [Yy]* )
                    git branch -D $lb
                    break
                    ;;
                * )
                    break
                    ;;
            esac
        done
    fi
done
echo "Done"
