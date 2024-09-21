#!/bin/bash
set -e

bash .utils/.check-workdir.sh

if [ "${1}" = "" ] || [ "${2}" = "" ] || [ "${3}" = "" ] || [ "${4}" = "" ] || [ "${5}" = "" ]; then
    echo "Usage: <path> <repo url> <branch> <subdir> <action>"
    exit
fi
path="${1}"
repo="${2}"
branch="${3}"
subdir="${4}"
action="${5}"

prevbranch="$(git branch --show-current)"
temp="$(rev <<< "${repo%/}" | cut -d/ -f1,2 | rev | tr / -)-$(tr / - <<< "${branch}")"
fetch="_fetch-${temp}"
split="_split-${temp}-$(tr / - <<< "${subdir}")"
git fetch --no-tags "${repo}" "${branch}:${fetch}"
cache="${path}/.subtree-cache/${split}"
hash="$(git rev-parse ${fetch})"
skip=false
if [ -f "${cache}" ]; then
    if git diff --quiet "$(<${cache})" "${hash}" -- "${subdir}"; then
        skip=true
    fi
fi
ok=true
if $skip; then
    echo "No updates, skipping expensive subtree split."
else
    git checkout "${fetch}"
    exec {capture}>&1
    result="$(git subtree split -P "${subdir}" -b "${split}" 2>&1 | tee /proc/self/fd/$capture)"
    if grep "is not an ancestor of commit" <<< "$result" > /dev/null; then
        echo "Resetting split branch..."
        git branch -D "${split}"
        git subtree split -P "${subdir}" -b "${split}"
    fi
    if grep "^fatal: " <<< "$result" > /dev/null; then
        ok=false
    fi
    git checkout "${prevbranch}"
    if $ok; then
        prevhead="$(git rev-parse HEAD)"
        exec {capture}>&1
        result="$(git subtree "${action}" -P "${path}" "${split}" -m "${action^} ${path} from ${repo}" 2>&1 | tee /proc/self/fd/$capture)"
        cleanmerge=false
        if git diff --quiet && git diff --cached --quiet && git merge HEAD &> /dev/null; then
            cleanmerge=true
        fi
        bash .utils/.check-merge.sh "${path}" "${repo}" "${result}"
        if [ "${prevhead}" = "$(git rev-parse HEAD)" ] && ! $cleanmerge; then
            # Not a clean merge, and merge was aborted, don't save cache
            ok=false
        fi
    fi
fi
if $ok; then
    mkdir -p "${path}/.subtree-cache"
    echo "${hash}" > "${cache}"
fi
