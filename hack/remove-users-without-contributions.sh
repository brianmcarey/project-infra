#!/usr/bin/env bash

set -euo pipefail

function usage() {
    cat << EOF

usage: $0 <input-file>

    Removes all users without contributions (taken from the input file) from the orgs.yaml

    input file in csv format is manually fetched from KubeVirt devstats:
    https://kubevirt.devstats.cncf.io/d/9/developer-activity-counts-by-repository-group-table?orgId=1&var-period_name=Last%20year&var-metric=contributions&var-repogroup_name=All&var-country_name=All&inspect=1&inspectTab=data

    then from the top panel select "Inspect" > "Data" and select "Download CSV"
EOF
}

if ! command -V yq; then
    echo "yq is required!"
    exit 1
fi
is_jq_wrapper="$(yq --help | grep -c 'jq wrapper for YAML documents')"

if [ "$#" -lt 1 ]; then
    echo "input-file is required"
    usage
    exit 1
fi

if [[ "$1" =~ -h ]]; then
    usage
    exit 0
fi

if [ ! -f "$1" ]; then
    echo "input-file $1 doesn't exist"
    usage
    exit 1
fi
input_csv_file="$1"

set -x

base_dir=$( cd $( dirname "${BASH_SOURCE[0]}") && pwd )

orgs_yaml_path="${base_dir}/../github/ci/prow-deploy/kustom/base/configs/current/orgs/orgs.yaml"
if [ ! -f "$orgs_yaml_path" ]; then
    echo "File $orgs_yaml_path not found!"
    exit 1
fi

# generate input file from csv where each user is in a separate line
tail --lines=+2 "${input_csv_file}" | \
    grep -vE '^:space:*$' | \
    cut -f 2 -d ',' \
    > /tmp/users-with-contributions.txt

### we add some user accounts, so that they never get removed

# bots (kubevirt, openshift, the linux foundation)
cat << EOF >> /tmp/users-with-contributions.txt
kubevirt-bot
kubevirt-commenter-bot
kubevirt-snyk
openshift-ci-robot
openshift-merge-robot
thelinuxfoundation
EOF

# KubeVirt org admins (security measure so that we don't lose GitHub org access)
cat << EOF >> /tmp/users-with-contributions.txt
brianmcarey
davidvossel
dhiller
fabiand
rmohr
EOF

# users with invisible contributions (i.e. OSPO, KubeVirt community manager etc)
cat << EOF >> /tmp/users-with-contributions.txt
aburdenthehand
jberkus
EOF

function get_yaml_elements() {
    if (( is_jq_wrapper == 1 )); then
        yq -r ".$1[]" "$orgs_yaml_path"
    else
        yq read "$orgs_yaml_path" "$1"
    fi
}

# iterate over org users (members and admins), grep over contributors list, remove every user not found
rm -f /tmp/users-without-contributions.txt
touch /tmp/users-without-contributions.txt
for username in $(
    { get_yaml_elements orgs.kubevirt.members & \
      get_yaml_elements orgs.kubevirt.admins ; \
    } | sed 's/^- //' | sort -u); do
    if (( $(grep -i -c "$username" /tmp/users-with-contributions.txt) == 0 )); then
        echo "$username" >> /tmp/users-without-contributions.txt
    fi
done

# remove all users without contributions
for user in $(cat /tmp/users-without-contributions.txt); do
    sed -i -E '/\s+- '"$user"'/d' "$orgs_yaml_path"
done

echo "users without contributions found: $(wc -l /tmp/users-without-contributions.txt)"
cat /tmp/users-without-contributions.txt
