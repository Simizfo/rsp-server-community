#!/bin/sh
repoOwnerAndName=redhat-developer/rsp-server-community
curBranch=`git rev-parse --abbrev-ref HEAD`
ghtoken=`cat ~/.keys/gh_access_token`
argsPassed=$#
echo "args: " $argsPassed
if [ "$argsPassed" -eq 1 ]; then
	debug=1
	echo "YOU ARE IN DEBUG MODE. Changes will NOT be pushed upstream"
else
	echo "The script is live. All changes will be pushed, deployed, etc. Live."
	debug=0
fi
read -p "Press enter to continue"


apiStatus=`git status -s | wc -l`
if [ $apiStatus -ne 0 ]; then
   echo "This repository has changes and we won't be able to auto upversion. Please commit or stash your changes and try again"
   exit 1
fi

echo ""
echo "These are the commits for the release"
commits=`git lg | grep -n -m 1 "Upversion to " |sed  's/\([0-9]*\).*/\1/' | tail -n 1`
commitMsgs=`git log --color --pretty=format:'%h - %s' --abbrev-commit | head -n $commits`
echo "$commitMsgs"
read -p "Press enter to continue"


cd rsp
oldverRspRaw=`cat pom.xml  | grep "version" | head -n 2 | tail -n 1 | cut -f 2 -d ">" | cut -f 1 -d "<" |  awk '{$1=$1};1'`
oldverRsp=`echo $oldverRspRaw | sed 's/\.Final//g' | sed 's/-SNAPSHOT//g'`
oldverRspHasSnapshot=`cat pom.xml  | grep "version" | head -n 2 | tail -n 1 | cut -f 2 -d ">" | cut -f 1 -d "<" | grep -i snapshot | awk '{$1=$1};1' | wc -c`


if [ "$oldverRspHasSnapshot" -eq 0 ]; then
	newLastSegmentRsp=`echo $oldverRspRaw | cut -f 3 -d "." | awk '{ print $0 + 1;}' | bc`
	newverPrefixRsp=`echo $oldverRspRaw | cut -f 1,2 -d "."`
	newverRsp=$newverPrefixRsp.$newLastSegmentRsp
else 
	newverRsp=$oldverRsp
fi
newverRspFinal=$newverRsp.Final

echo "Old version (RSP) is $oldverRspRaw"
echo "New version (RSP) is $newverRspFinal"
echo "Updating pom.xml with new version"
mvn org.eclipse.tycho:tycho-versions-plugin:1.3.0:set-version -DnewVersion=$newverRspFinal

# Handle target platform
tpFile=`ls -1 targetplatform | grep target`
cat targetplatform/$tpFile | sed "s/-target-$oldver/-target-$newver/g" > targetplatform/$tpFile.bak
mv targetplatform/$tpFile.bak targetplatform/$tpFile
echo ""
echo "Did you require upstream changes from rsp-server?? If yes,"
echo "Please go update the TP to depend on newest rsp-server if required"
read -p "Press enter to continue"


echo "Lets build the RSP"
read -p "Press enter to continue"
mvn clean install -DskipTests
echo "Did it succeed?"
read -p "Press enter to continue"

echo ""
echo "Looks like its time to build the extension now"
read -p "Press enter to continue"

cd ../vscode/

oldvervsc=`cat package.json  | grep "\"version\":" | cut -f 2 -d ":" | sed 's/"//g' | sed 's/,//g' | awk '{$1=$1};1'`

echo "Old version [vsc extension] is $oldvervsc"
echo "Running npm install"
npm install

npm run build
echo "Did it succeed?"
read -p "Press enter to continue"

echo "Running vsce package"
vsce package
echo "Did it succeed?"
read -p "Press enter to continue"


echo "Go kick a Jenkins Job please. Come back when its DONE and green."
read -p "Press enter to continue"


oldVerVscUnderscore=`echo $oldvervsc | sed 's/\./_/g'`
oldVerVscFinal=$oldvervsc.Final
vscTagName=v$oldVerVscUnderscore.Final

echo "Committing and pushing to $curBranch"
git commit -a -m "Move extension to $vscTagName for release" --signoff

if [ "$debug" -eq 0 ]; then
	git push origin $curBranch
else 
	echo git push origin $curBranch
fi


echo "Go kick another jenkins job with a release flag."
read -p "Press enter to continue"



echo "Are you absolutely sure you want to tag?"
read -p "Press enter to continue"

git tag $vscTagName
if [ "$debug" -eq 0 ]; then
	git push origin $vscTagName
else 
	echo git push origin $vscTagName
fi


echo "Making a release on github for $oldVerVscFinal"
commitMsgsClean=`git log --color --pretty=format:'%s' --abbrev-commit | head -n $commits | awk '{ print " * " $0;}' | awk '{printf "%s\\\\n", $0}' | sed 's/"/\\"/g'`
createReleasePayload="{\"tag_name\":\"$vscTagName\",\"target_commitish\":\"$curBranch\",\"name\":\"$oldVerVscFinal\",\"body\":\"Release of $oldVerVscFinal:\n\n"$commitMsgsClean"\",\"draft\":false,\"prerelease\":false,\"generate_release_notes\":false}"

if [ "$debug" -eq 0 ]; then
	curl -L \
	  -X POST \
	  -H "Accept: application/vnd.github+json" \
	  -H "Authorization: Bearer $ghtoken"\
	  -H "X-GitHub-Api-Version: 2022-11-28" \
	  https://api.github.com/repos/$repoOwnerAndName/releases \
	  -d "$createReleasePayload" | tee createReleaseResponse.json
else 
	echo curl -L \
	  -X POST \
	  -H "Accept: application/vnd.github+json" \
	  -H "Authorization: Bearer $ghtoken"\
	  -H "X-GitHub-Api-Version: 2022-11-28" \
	  https://api.github.com/repos/$repoOwnerAndName/releases \
	  -d "$createReleasePayload"
fi

echo "Please go verify the release looks correct. We will add the asset next"
read -p "Press enter to continue"


assetUrl=`cat createReleaseResponse.json | grep assets_url | cut -c 1-17 --complement | rev | cut -c3- | rev | sed 's/api.github.com/uploads.github.com/g'`
rm createReleaseResponse.json
zipFileName=` ls -1 -t *.vsix  | head -n 1`
echo "Running command to add artifact to release: "
	echo curl -L \
	  -X POST \
	  -H "Accept: application/vnd.github+json" \
	  -H "Authorization: Bearer $ghtoken"\
	  -H "X-GitHub-Api-Version: 2022-11-28" \
	  -H "Content-Type: application/octet-stream" \
	  $assetUrl?name=$zipFileName \
	  --data-binary "@$zipFileName"
if [ "$debug" -eq 0 ]; then
	curl -L \
	  -X POST \
	  -H "Accept: application/vnd.github+json" \
	  -H "Authorization: Bearer $ghtoken"\
	  -H "X-GitHub-Api-Version: 2022-11-28" \
	  -H "Content-Type: application/octet-stream" \
	  $assetUrl?name=$zipFileName \
	  --data-binary "@$zipFileName"
fi
echo ""
echo "Please go verify the release looks correct and the distribution was added correctly."
read -p "Press enter to continue"


echo ""
echo ""
echo "Time to update versions for development"
read -p "Press enter to continue"

cd ../rsp
echo "First the rsp"
read -p "Press enter to continue"
nextLastSegmentRsp=`echo $newverRsp | cut -f 3 -d "." | awk '{ print $0 + 1;}' | bc`
nextVerPrefixRsp=`echo $newverRsp | cut -f 1,2 -d "."`
nextVerRsp=$nextVerPrefixRsp.$nextLastSegmentRsp

echo "Current version (RSP) is $newverRsp"
echo "Next version (RSP) is $nextVerRsp"
echo "Updating pom.xml with new version"
mvn org.eclipse.tycho:tycho-versions-plugin:1.3.0:set-version -DnewVersion=$nextVerRsp-SNAPSHOT

# Handle target platform
tpFile=`ls -1 targetplatform | grep target`
cat targetplatform/$tpFile | sed "s/-target-$newverRsp.Final/-target-$nextVerRsp-SNAPSHOT/g" > targetplatform/$tpFile.bak
mv targetplatform/$tpFile.bak targetplatform/$tpFile

echo "Lets build the RSP After upversion"
read -p "Press enter to continue"
mvn clean install -DskipTests
echo "Did it succeed?"
read -p "Press enter to continue"

cd ../vscode
newVscVer=`cat package.json  | grep "\"version\":" | cut -f 2 -d ":" | sed 's/"//g' | sed 's/,//g' | awk '{$1=$1};1'`
newVscLastSegment=`echo $newVscVer | cut -f 3 -d "." | awk '{ print $0 + 1;}' | bc`
newVscPrefix=`echo $newVscVer | cut -f 1,2 -d "."`
newVsc=$newVscPrefix.$newVscLastSegment
echo "New version is $newVsc"

echo "Updating package.json with new version"
cat package.json | sed "s/\"version\": \"$newVscVer\",/\"version\": \"$newVsc\",/g" > package2
mv package2 package.json


echo "Committing and pushing to $curBranch"
git commit -a -m "Upversion to $newVsc - Development Begins" --signoff

if [ "$debug" -eq 0 ]; then
	git push origin $curBranch
else 
	echo git push origin $curBranch
fi

