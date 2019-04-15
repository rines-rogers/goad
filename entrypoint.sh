#!/bin/bash

GOAD_BIN="/go/src/github.com/goadapp/goad/build/linux/x86-64/goad"
TIMESTAMP="$(date +"%s")"
: "${S3_RESULTS_BUCKET:=s3://zype-goad-cdn-tester-results}"
: "${REGIONS:=us-east-1 us-west-1 ap-northeast-1 eu-west-1}"
: "${REQUESTS:=100}"
: "${CONCURRENCY:=1}"

if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
  (>&2 echo "Must provide AWS_ACCESS_KEY_ID")
  exit 1
fi

if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  (>&2 echo "Must provide AWS_SECRET_ACCESS_KEY")
  exit 1
fi

if [[ -z "$VIDEO_ID" ]]; then
  (>&2 echo "Must provide VIDEO_ID")
  exit 1
fi

if [[ -z "$ZYPE_API_KEY" ]]; then
  (>&2 echo "Must provide ZYPE_API_KEY")
  exit 1
fi

if [[ -z "$VIDEO_MODE" ]]; then
  (>&2 echo "Must provide VIDEO_MODE")
  exit 1
fi

if [[ -z "$PLATFORM" ]]; then
  (>&2 echo "Must provide PLATFORM")
  exit 1
fi

# Set up results path
rm -rf /tmp/goad-results
mkdir /tmp/goad-results

# Find the right user agent
USER_AGENT=""
case $PLATFORM in
ios_html5)
  USER_AGENT="Mozilla/5.0 (iPhone; CPU iPhone OS 12_1_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.0 Mobile/15E148 Safari/604.1"
  ;;
ios_native)
  USER_AGENT="BodyFX/13 CFNetwork/976 Darwin/18.2.0"
  ;;
android_native)
  USER_AGENT="Dalvik/2.1.0 (Zype Android; Linux; U; Android 5.0.2; One X Build/LRX22G)"
  ;;
firetv)
  USER_AGENT="Mozilla/5.0 (Linux; Android 5.1.1; AFTT Build/LVY48F; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/59.0.3071.125 Mobile Safari/537.36 cordova-amazon-fireos/3.4.0 AmazonWebAppPlatform/3.4.0;2.0"
  ;;
roku)
  USER_AGENT="Roku/DVP-9.0 (519.00E04142A)"
  ;;
appletv)
  USER_AGENT="zype tvos"
  ;;
smarttv)
  USER_AGENT="Mozilla/5.0 (SMART-TV; Linux; Tizen 3.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/2.0 Chrome/47.0.2526.69 TV safari/537.36"
  ;;
desktop)
  USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Safari/537.36"
  ;;
*)
  (>&2 echo "Invalid platform $PLATFORM")
  exit 1
  ;;
esac

case $VIDEO_MODE in
vod)
  # Download the master manifest directly
  curl -A "$USER_AGENT" "https://player.zype.com/manifest/$VIDEO_ID?api_key=$ZYPE_API_KEY" > /tmp/master_manifest.out
  ;;
live)
  # We currently need the JSON embed code, which is returned on any non-desktop platform.
  if [ "$PLATFORM" == "desktop" ]; then
    (>&2 echo "Live testing with desktop platform is currently unsupported.")
    exit 1
  fi

  # Download the JSON embed code, then parse the master manifest URL and download it
  MANIFEST_URL=`curl -A "$USER_AGENT" "https://player.zype.com/embed/$VIDEO_ID?api_key=$ZYPE_API_KEY" | jq -r '.response.body.outputs[0].url'`
  curl -A "$USER_AGENT" "$MANIFEST_URL" > /tmp/master_manifest.out
  ;;
*)
  (>&2 echo "Invalid video mode $VIDEO_MODE")
  exit 1
  ;;
esac

# Look for the x720 resolution and store that URL.
found_url=0
CHILD_MANIFEST_URL=""
while read line
do
  if [ $found_url -eq 1 ]; then
    CHILD_MANIFEST_URL=$line
    break
  fi
  if [[ "$line" == *"RESOLUTION="* && "$line" == *"x720"* ]]; then
    found_url=1
  fi
done < <(cat /tmp/master_manifest.out)

# Download the child manifest and store the URL of the first chunk.
curl -A "$USER_AGENT" "$CHILD_MANIFEST_URL" > /tmp/child_manifest.out
found_url=0
CHUNK_MANIFEST_URL=""
while read line
do
  if [ $found_url -eq 1 ]; then
    CHUNK_MANIFEST_URL=$line
    break
  fi
  if [[ "$line" == *"#EXTINF"* ]]; then
    found_url=1
  fi
done < <(cat /tmp/child_manifest.out)

# Use that chunk URL for testing. Run it through every configured region and store the test results.
for r in $REGIONS; do
  $GOAD_BIN -H "User-Agent: $USER_AGENT" -H "Zype-Info: Goad Test ($r)" --region=$r --requests=$REQUESTS --concurrency=$CONCURRENCY --json-output=/tmp/goad-results/$VIDEO_ID.$r.$PLATFORM-$VIDEO_MODE.$TIMESTAMP.json "$CHUNK_MANIFEST_URL";
done

# Upload the test results to S3.
cd /tmp/goad-results/
RESULT_FILES=/tmp/goad-results/*
for f in $RESULT_FILES; do
  echo "Uploading $f..."
  s3cmd put $f $S3_RESULTS_BUCKET
done
