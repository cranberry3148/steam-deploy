#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

steamdir=${STEAM_HOME:-$HOME/Steam}
# this is relative to the action
if [[ "$rootPath" = /* ]]; then
    contentroot="$rootPath"
else
    contentroot="$(pwd)/$rootPath"
fi

# these are temporary file we create, so in a tmpdir
build_output_path=$(mktemp -d)/BuildOutput
mkdir -p $build_output_path
manifest_path=$(pwd)/manifest.vdf

echo ""
echo "#################################"
echo "#   Generating Depot Manifests  #"
echo "#################################"
echo ""

if [ -n "$firstDepotIdOverride" ]; then
  firstDepotId=$firstDepotIdOverride
else
  # The first depot ID of a standard Steam app is the app's ID plus one
  firstDepotId=$((appId + 1))
fi

i=1;
export DEPOTS="\n  "
until [ $i -gt 9 ]; do
  eval "currentDepotPath=\$depot${i}Path"
  eval "currentDepotInstallScriptPath=\$depot${i}InstallScriptPath"
  if [ -n "$currentDepotPath" ]; then
    # depot1Path uses firstDepotId, depot2Path uses firstDepotId + 1, depot3Path uses firstDepotId + 2...
    currentDepot=$((firstDepotId + i - 1))

    # If the depot has an install script, add it to the depot manifest
    if [ -n "${currentDepotInstallScriptPath:-}" ]; then
      echo ""
      echo "Adding install script for depot ${currentDepot}..."
      echo ""
      installScriptDirective="\"InstallScript\" \"${currentDepotInstallScriptPath}\""
    else
      installScriptDirective=""
    fi

    echo ""
    echo "Adding depot${currentDepot}.vdf ..."
    echo ""
    export DEPOTS="$DEPOTS  \"$currentDepot\" \"depot${currentDepot}.vdf\"\n  "

    cat << EOF > "depot${currentDepot}.vdf"
"DepotBuildConfig"
{
  "DepotID" "$currentDepot"
  "FileMapping"
  {
    "LocalPath" "./$currentDepotPath/*"
    "DepotPath" "."
    "recursive" "1"
  }
  "FileExclusion" "*.pdb"
  "FileExclusion" "**/*_BurstDebugInformation_DoNotShip*"
  "FileExclusion" "**/*_BackUpThisFolder_ButDontShipItWithYourGame*"

  $installScriptDirective
}
EOF

  cat depot${currentDepot}.vdf
  echo ""
  fi;

  i=$((i+1))
done

echo ""
echo "#################################"
echo "#    Generating App Manifest    #"
echo "#################################"
echo ""

cat << EOF > "manifest.vdf"
"appbuild"
{
  "appid" "$appId"
  "desc" "$buildDescription"
  "buildoutput" "$build_output_path"
  "contentroot" "$contentroot"
  "setlive" "$releaseBranch"

  "depots"
  {$(echo "$DEPOTS" | sed 's/\\n/\
/g')}
}
EOF

cat manifest.vdf
echo ""

if [ -n "$steam_shared_secret" ]; then
  echo ""
  echo "##########################################"
  echo "#     Using SteamGuard Shared Secret     #"
  echo "##########################################"
  echo ""
else
  echo "Shared Secret input is missing or incomplete! Cannot proceed."
  exit 1
fi

echo ""
echo "#################################"
echo "#        Test login             #"
echo "#################################"
echo ""

wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

nvm install stable

cp /root/package.json ./package.json
cp /root/totp.js ./totp.js

npm i
export steam_totp="$(node totp.js)"
echo $steam_totp

steamcmd steamcmd +login "$steam_username" "$steam_password" "$steam_totp" +quit;

ret=$?
if [ $ret -eq 0 ]; then
    echo ""
    echo "#################################"
    echo "#        Successful login       #"
    echo "#################################"
    echo ""
else
      echo ""
      echo "#################################"
      echo "#        FAILED login           #"
      echo "#################################"
      echo ""
      echo "Exit code: $ret"

      exit $ret
fi

echo ""
echo "#################################"
echo "#        Uploading build        #"
echo "#################################"
echo ""

steamcmd +login "$steam_username" +run_app_build "$manifest_path" +quit || (
    echo ""
    echo "#################################"
    echo "#             Errors            #"
    echo "#################################"
    echo ""
    echo "Listing current folder and rootpath"
    echo ""
    ls -alh
    echo ""
    ls -alh "$rootPath" || true
    echo ""
    echo "Listing logs folder:"
    echo ""
    ls -Ralph "$steamdir/logs/"

    for f in "$steamdir"/logs/*; do
      if [ -e "$f" ]; then
        echo "######## $f"
        cat "$f"
        echo
      fi
    done

    echo ""
    echo "Displaying error log"
    echo ""
    cat "$steamdir/logs/stderr.txt"
    echo ""
    echo "Displaying bootstrapper log"
    echo ""
    cat "$steamdir/logs/bootstrap_log.txt"
    echo ""
    echo "#################################"
    echo "#             Output            #"
    echo "#################################"
    echo ""
    ls -Ralph $build_output_path

    for f in $build_output_path/*.log; do
      echo "######## $f"
      cat "$f"
      echo
    done

    exit 1
  )

echo "manifest=${manifest_path}" >> $GITHUB_OUTPUT
