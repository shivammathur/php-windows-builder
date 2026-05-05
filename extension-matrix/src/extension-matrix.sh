#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

. "$SCRIPT_DIR"/php-versions.sh

matrix=();

[ -z "$EXTENSION_URL" ] && EXTENSION_URL="https://github.com/${GITHUB_REPOSITORY:?}"
[ -z "$EXTENSION_REF" ] && EXTENSION_REF="${GITHUB_SHA:?}"

[ -z "$PHP_VERSION_LIST" ] && \
  PHP_VERSION_LIST="$(get_php_versions "$EXTENSION_URL" "$EXTENSION_REF")"
[ -z "$ARCH_LIST" ] && ARCH_LIST="x64,x86"
[ -z "$TS_LIST" ] && TS_LIST="nts,ts"

IFS=',' read -r -a php_version_array <<<"${PHP_VERSION_LIST// /}"
IFS=',' read -r -a arch_array <<<"${ARCH_LIST// /}"
IFS=',' read -r -a ts_array <<<"${TS_LIST// /}"

vs_json="$SCRIPT_DIR"/../config/vs.json
vs_toolset_json="$SCRIPT_DIR"/../../extension/BuildPhpExtension/config/vs.json
filtered_versions=$(jq -r 'keys | join(" ")' "$vs_json")
if [[ -z "$ALLOW_OLD_PHP_VERSIONS" || "$ALLOW_OLD_PHP_VERSIONS" == "false" ]]; then
  filtered_versions=$(jq -r 'to_entries | map(select(.value.type == "github-hosted") | .key) | join(" ")' "$vs_json")
fi

found='false'
vs_cache_savers=' '
for php_version in "${php_version_array[@]}"; do
  if [[ " $filtered_versions " =~ $php_version ]]; then
    found='true'
  else
    continue
  fi
  os=$(jq -r --arg php_version "$php_version" '.[$php_version].os' "$vs_json")
  vs_toolset=''
  if [[ -f "$vs_toolset_json" ]]; then
    vs_toolset=$(jq -r --arg php_version "$php_version" '.php[$php_version] // empty' "$vs_toolset_json")
  fi
  if [[ -z "$vs_toolset" ]]; then
    vs_toolset=$(jq -r --arg php_version "$php_version" '.[$php_version].vs' "$vs_json")
  fi
  for arch in "${arch_array[@]}"; do
    for ts in "${ts_array[@]}"; do
      vs_cache_key="$os-$vs_toolset"
      save_vs_cache='false'
      if [[ "$vs_cache_savers" != *" $vs_cache_key "* ]]; then
        save_vs_cache='true'
        vs_cache_savers+="$vs_cache_key "
      fi
      matrix+=("{\"os\": \"$os\", \"php-version\": \"$php_version\", \"arch\": \"$arch\", \"ts\": \"$ts\", \"save-vs-cache\": $save_vs_cache}")
    done
  done
done

if [[ "$found" == 'false' ]]; then
  echo "No PHP versions found for the specified inputs"
  echo "Please refer to the PHP version support in the README"
  echo "https://github.com/php/php-windows-builder#php-version-support"
  exit 1
fi

# shellcheck disable=SC2001
echo "matrix={\"include\":[$(echo "${matrix[@]}" | sed -e 's|} {|}, {|g')]}" >> "$GITHUB_OUTPUT"
