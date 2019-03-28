#!/bin/bash

GOAD_BIN="/go/src/github.com/goadapp/goad/build/linux/x86-64/goad"
TIMESTAMP="$(date +"%s")"
: "${S3_RESULTS_BUCKET:=s3://zype-goad-cdn-tester-results}"
: "${REGIONS:=us-east-1 us-west-1 ap-northeast-1 eu-west-1}"
: "${REQUESTS:=1000}"
: "${CONCURRENCY:=10}"
: "${TARGET_URL:=https://admin.zype.com/uploads/5b1ef0c1f7f370125e000bfd/download_original}"

if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
  (>&2 echo "Must provide AWS_ACCESS_KEY_ID")
  exit 1
fi

if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
  (>&2 echo "Must provide AWS_SECRET_ACCESS_KEY")
  exit 1
fi


rm -rf /tmp/goad-results
mkdir /tmp/goad-results

for r in $REGIONS; do
  $GOAD_BIN --region=$r --requests=$REQUESTS --concurrency=$CONCURRENCY --json-output=/tmp/goad-results/$r.$TIMESTAMP.json "$TARGET_URL";
done

cd /tmp/goad-results/
RESULT_FILES=/tmp/goad-results/*

for f in $RESULT_FILES; do
  echo "Uploading $f..."
  s3cmd put $f $S3_RESULTS_BUCKET
done
